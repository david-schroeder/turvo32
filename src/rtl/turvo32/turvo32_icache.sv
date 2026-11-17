// SPDX-License-Identifier: SHL-2.1
// SPDX-FileCopyrightText: David Schröder 2026

module turvo32_icache
    import turvo32_pkg::*;
    import tilelink_pkg::*;
#(
    parameter int LINE_WORDS = 8,
    parameter int SETS = 128,
    parameter int WAYS = 2
) (
    input  logic clk_i,
    input  logic rst_ni,

    // control signals
    input  logic        flush_i,
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

    ///////////////////////////
    //                       //
    // Address decomposition //
    //                       //
    ///////////////////////////

    localparam BO_W = $clog2(LINE_WORDS);
    localparam IDX_W = $clog2(SETS);
    localparam TAG_W = 30 - BO_W - IDX_W;

    logic [ BO_W-1:0] pc_d_bo,  pc_if_bo,  pc_miss_bo;
    logic [IDX_W-1:0] pc_d_idx, pc_if_idx, pc_miss_idx;
    logic [TAG_W-1:0] pc_d_tag, pc_if_tag, pc_miss_tag;

    assign {pc_d_tag, pc_d_idx, pc_d_bo} = pc_d_i[31:2];

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (~rst_ni) begin
            pc_if_bo    <= '0;
            pc_if_idx   <= '0;
            pc_if_tag   <= '0;
        end else begin
            // pc_if_* update is not gated on stall
            // this enables non-blocking behavior
            pc_if_bo  <= pc_d_bo;
            pc_if_idx <= pc_d_idx;
            pc_if_tag <= pc_d_tag;
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

    cache_state_e state_d, state_q, state_q_q;
    logic miss, miss_first_cycle;

    // not BO_W-1:0 because they must be able to hold BO_W as a value
    logic [BO_W:0] issued_reqs_d, issued_reqs_q;
    logic [BO_W:0] arrived_rsps_d, arrived_rsps_q;

    always_comb begin
        state_d = state_q;
        issued_reqs_d = issued_reqs_q;
        arrived_rsps_d = arrived_rsps_q;
        miss = '0;
        miss_first_cycle = '0;

        if (tl_o.a_valid && tl_i.a_ready) issued_reqs_d = issued_reqs_q + 1;
        if (tl_i.d_valid && tl_o.d_ready) arrived_rsps_d = arrived_rsps_q + 1;

        case (state_q)
            Idle: begin
                if (stall_if_o) begin
                    state_d = Fetching;
                    miss = '1;
                    miss_first_cycle = '1;
                end
            end
            Fetching: begin
                if (issued_reqs_d == LINE_WORDS) state_d = Receiving;
                miss = '1;
            end
            Receiving: begin
                if (arrived_rsps_d == LINE_WORDS) state_d = Idle;
                miss = '1;
            end
        endcase
    end

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (~rst_ni) begin
            pc_miss_tag    <= '0;
            pc_miss_idx    <= '0;
            pc_miss_bo     <= '0;
            state_q        <= Idle;
            state_q_q      <= Idle;
            issued_reqs_q  <= '0;
            arrived_rsps_q <= '0;
        end else begin
            state_q        <= state_d;
            state_q_q      <= state_q;
            issued_reqs_q  <= issued_reqs_d;
            arrived_rsps_q <= arrived_rsps_d;

            case (state_q)
                Idle: begin
                    pc_miss_tag    <= pc_d_tag;
                    pc_miss_idx    <= pc_d_idx;
                    pc_miss_bo     <= pc_d_bo;
                    arrived_rsps_q <= '0;
                end
                Receiving: issued_reqs_q <= '0;
            endcase
        end
    end

    assign stall_if_o = valid_if_i && cacheable_if_i && ~hit_o;

    ////////////////////////////////////
    //                                //
    // Misc. TileLink Interface Logic //
    //                                //
    ////////////////////////////////////

    // TileLink source field <-> block offset mapping
    // remapped s.t. source 0 = block offset of miss (critical word)
    // thus allowing critical word first fetching
    logic [BO_W-1:0] req_bo, rsp_bo, rsp_bo_q;
    assign req_bo = pc_miss_bo + issued_reqs_q;
    assign rsp_bo = tl_i.d_source - pc_miss_bo;

    logic [31:0] tli_data_q;

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if(~rst_ni) begin
            rsp_bo_q   <= '0;
            tli_data_q <= '0;
        end else begin
            rsp_bo_q   <= rsp_bo;
            tli_data_q <= tl_i.d_data;
        end
    end

    assign tl_o = '{
        a_valid: state_q == Fetching,
        a_opcode: Get,
        a_size: 2'h2,
        a_source: issued_reqs_q,
        a_address: {
            pc_miss_tag,
            pc_miss_idx,
            req_bo,
            2'h0
        },
        d_ready: '1,
        default: '0
    };

    ////////////////////
    //                //
    // Way Generation //
    //                //
    ////////////////////

    logic [31:0] rdata_ways     [WAYS-1:0];
    logic [31:0] rdata_ways_byp [WAYS-1:0]; // rdata_ways with fetch bypasses
    logic        hit_ways       [WAYS-1:0];

    // IDs of ways
    logic [$clog2(WAYS)-1:0] lru_way, evict_way_q; // evict_way_q ~= lru_way_q
    logic [$clog2(WAYS)-1:0] way_to_evict; // replaced way during eviction
    logic [$clog2(WAYS)-1:0] hit_way;

    always_comb begin
        instr_o = '0;
        hit_o   = '0;
        hit_way = way_to_evict;
        for (int i = 0; i < WAYS; i++) begin
            if (hit_ways[i]) begin
                instr_o = rdata_ways_byp[i];
                hit_way = i;
                hit_o   = '1;
            end
        end
    end

    generate
        for (genvar i = 0; i < WAYS; i++) begin : gen_ways

            /* Declarations */

            logic             valid [SETS-1:0];
            logic [TAG_W-1:0] tags  [SETS-1:0];
            logic [     31:0] lines [SETS*LINE_WORDS-1:0];

            logic [TAG_W-1:0] tag_rdata;
            logic             valid_rdata;


            /* Combinational hit + rdata generation */

            always_comb begin
                rdata_ways_byp[i] = rdata_ways[i];
                // simple case: check tag + valid bit
                hit_ways[i] = valid_rdata && tag_rdata == pc_if_tag;

                if (state_q_q != Idle && evict_way_q == i) begin
                    // bypass case for demand-fetched blocks:
                    // if we're not in idle state and pc_if_{tag, idx} match
                    // pc_miss_{tag, idx}, pc_if_bo is checked against
                    // the already arrived word count
                    // we also want to do the bypass check in the cycle after
                    // the final cycle of a demand fetch, thus state_q_q
                    // Accounting for the CWF scheduling approach, this means
                    // taking pc_if_bo - pc_miss_bo to derive the position in
                    // the fetch sequence of the requested block
                    // if it is strictly less than arrived_rsps_q, we have
                    // a hit
                    if ({pc_if_tag, pc_if_idx} == {pc_miss_tag, pc_miss_idx}) begin
                        hit_ways[i] = pc_if_bo - pc_miss_bo < arrived_rsps_q;
                        if (pc_if_bo - pc_miss_bo < arrived_rsps_q) begin
                            if (pc_if_bo == rsp_bo_q) begin
                                rdata_ways_byp[i] = tli_data_q;
                            end
                        end
                    end
                end
            end


            /* Valid bit management */

            // TODO: think about using a denser primitive for this?

            always_ff @(posedge clk_i or negedge rst_ni) begin
                if (~rst_ni) begin
                    valid <= '{default: '0};
                    valid_rdata <= '0;
                end else begin
                    valid_rdata <= valid[pc_d_idx];
                    if (way_to_evict == i) begin
                        if (state_q == Receiving && state_d == Idle) begin
                            valid[pc_miss_idx] <= '1;
                        end
                    end
                end
            end


            /* Block RAM management */

            always_ff @(posedge clk_i) begin
                tag_rdata     <= tags[pc_d_idx];
                rdata_ways[i] <= lines[{pc_d_idx, pc_d_bo}];
                if (miss_first_cycle && way_to_evict == i) begin
                    tags[pc_if_idx] <= pc_if_tag;
                end
                if (tl_i.d_valid && tl_o.d_ready && evict_way_q == i) begin
                    lines[{pc_miss_idx, rsp_bo}] <= tl_i.d_data;
                end
            end

        end : gen_ways
    endgenerate

    //////////////////////////
    //                      //
    // LRU + Way management //
    //                      //
    //////////////////////////

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (~rst_ni) evict_way_q <= '0;
        else if (miss_first_cycle) evict_way_q <= lru_way;
    end

    assign way_to_evict = miss_first_cycle ? lru_way : evict_way_q;

    turvo32_lru #(
        .WAYS   (WAYS),
        .ENTRIES(SETS)
    ) eviction_lru_i (
        .clk_i,
        .rst_ni,
        .r_addr_i  (pc_d_idx),
        .lru_way_o (lru_way),
        .use_i     (hit_o),
        .use_way_i (hit_way),
        .use_addr_i(pc_if_idx)
    );

endmodule
