// SPDX-License-Identifier: SHL-2.1
// SPDX-FileCopyrightText: David Schröder 2026

module turvo32_icache
    import turvo32_pkg::*;
    import tilelink_pkg::*;
#(
    parameter int LINE_WORDS = 8,
    parameter int SETS = 64,
    parameter int WAYS = 2
) (
    input  logic clk_i,
    input  logic rst_ni,

    // control signals
    input  logic        flush_i,
    input  logic        update_i,
    output logic        stall_if_o,

    // IFU interface
    input  logic [31:0] pc_d_i,
    output logic [31:0] instr_o,
    output logic        hit_o,
    input  logic        cacheable_if_i,
    input  logic        valid_if_i,

    // Backend interface
    output tl_h2d_t     tl_o,
    input  tl_d2h_t     tl_i
);

    logic update_q;

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (~rst_ni) update_q <= '0;
        else update_q <= update_i;
    end

    ///////////////////////////
    //                       //
    // Address decomposition //
    //                       //
    ///////////////////////////

    localparam BO_W = $clog2(LINE_WORDS);
    localparam IDX_W = $clog2(SETS);
    localparam TAG_W = 30 - BO_W - IDX_W;

    logic [ BO_W-1:0] pc_d_bo,  pc_if_bo;
    logic [IDX_W-1:0] pc_d_idx, pc_if_idx;
    logic [TAG_W-1:0] pc_d_tag, pc_if_tag;

    assign {pc_d_tag, pc_d_idx, pc_d_bo} = pc_d_i[31:2];

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (~rst_ni) begin
            pc_if_bo  <= '0;
            pc_if_idx <= '0;
            pc_if_tag <= '0;
        end else begin
            if (update_i) begin
                pc_if_bo  <= pc_d_bo;
                pc_if_idx <= pc_d_idx;
                pc_if_tag <= pc_d_tag;
            end
        end
    end

    ///////////////
    //           //
    // FSM Logic //
    //           //
    ///////////////

    typedef enum logic [1:0] {
        Idle,
        Fetching,
        Receiving
    } cache_state_e;

    logic [BO_W-1:0] issued_reqs_d, issued_reqs_q;
    logic [BO_W-1:0] arrived_rsps_d, arrived_rsps_q;

    cache_state_e state_d, state_q;

    logic miss, miss_first_cycle;
    assign miss = update_q && !hit_o;
    assign miss_first_cycle = miss && state_q == Idle;

    always_comb begin
        state_d = state_q;
        issued_reqs_d = issued_reqs_q;
        arrived_rsps_d = arrived_rsps_q;

        if (tl_o.a_valid && tl_i.a_ready) issued_reqs_d = issued_reqs_q + 1;
        if (tl_i.d_valid && tl_o.d_ready) arrived_rsps_d = arrived_rsps_q + 1;

        case (state_q)
            Idle: begin
                if (miss) state_d = Fetching;
            end
            Fetching: begin
                if (issued_reqs_d == LINE_WORDS) state_d = Receiving;
            end
            Receiving: begin
                if (arrived_rsps_d == LINE_WORDS) state_d = Idle;
            end
        endcase
    end

    assign tl_o = '{
        a_valid: state_q == Fetching,
        a_opcode: Get,
        a_size: 2'h2,
        a_source: issued_reqs_q,
        a_address: {pc_if_tag, pc_if_idx, issued_reqs_q},
        d_ready: '1,
        default: '0
    };

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (~rst_ni) begin
            state_q <= Idle;
            issued_reqs_q <= '0;
            arrived_rsps_q <= '0;
        end else begin
            state_q <= state_d;
            issued_reqs_q <= issued_reqs_d;
            arrived_rsps_q <= arrived_rsps_d;

            case (state_q)
                Idle: arrived_rsps_q <= '0;
                Receiving: issued_reqs_q <= '0;
            endcase
        end
    end

    ////////////////////
    //                //
    // Way generation //
    //                //
    ////////////////////

    logic [31:0] rdata_ways [WAYS-1:0];
    logic        hit_ways   [WAYS-1:0];

    logic [$clog2(WAYS)-1:0] way_to_evict;
    logic [$clog2(WAYS)-1:0] hit_way;
    logic                    do_eviction;

    always_comb begin
        instr_o = '0;
        hit_o   = '0;
        hit_way = way_to_evict;
        for (int i = 0; i < WAYS; i++) begin
            if (hit_ways[i]) begin
                instr_o = rdata_ways[i];
                hit_way = i;
                hit_o   = '1;
            end
        end
    end

    assign stall_if_o = !hit_o && update_q;

    generate
        for (genvar i = 0; i < WAYS; i++) begin : gen_ways
            /* memories */
            logic             valid [SETS-1:0];
            logic [TAG_W-1:0] tags  [SETS-1:0];
            logic [     31:0] lines [SETS*LINE_WORDS-1:0];

            logic [TAG_W-1:0] tag_rdata;
            logic             valid_rdata;

            assign hit_ways[i] = valid_rdata && tag_rdata == pc_if_tag;

            always_ff @(posedge clk_i or negedge rst_ni) begin
                if (~rst_ni) begin
                    valid <= '{default: '0};
                    valid_rdata <= '0;
                end else begin
                    if (update_i) begin
                        valid_rdata <= valid[pc_d_idx];
                    end
                    if (way_to_evict == i) begin
                        if (miss_first_cycle) begin
                            valid[pc_if_idx] <= '0;
                        end else if (state_q == Receiving && state_d == Idle) begin
                            valid[pc_if_idx] <= '1;
                        end
                    end
                end
            end

            always_ff @(posedge clk_i) begin
                if (update_i) begin
                    tag_rdata     <= tags[pc_d_idx];
                    rdata_ways[i] <= lines[{pc_d_idx, pc_d_bo}];
                end
                if (miss_first_cycle && way_to_evict == i) begin
                    tags[pc_if_idx] <= pc_if_tag;
                end
                if (tl_i.d_valid && tl_o.d_ready) begin
                    lines[{pc_if_idx, tl_i.d_source}] <= tl_i.d_data;
                end
            end
        end : gen_ways
    endgenerate

    turvo32_lru #(
        .WAYS   (WAYS),
        .ENTRIES(SETS)
    ) eviction_lru_i (
        .clk_i,
        .rst_ni,
        .r_addr_i  (pc_d_idx),
        .lru_way_o (way_to_evict),
        .use_i     (hit_o),
        .use_way_i (hit_way),
        .use_addr_i(pc_d_idx)
    );

endmodule
