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

    ////////////////////
    //                //
    // Way generation //
    //                //
    ////////////////////

    logic [31:0] rdata_ways [WAYS-1:0];
    logic        hit_ways   [WAYS-1:0];

    assign hit_o = |hit_ways;

    always_comb begin
        instr_o = '0;
        for (int i = 0; i < WAYS; i++) begin
            if (hit_ways[i]) instr_o = rdata_ways[i];
        end
    end

    generate
        for (genvar i = 0; i < WAYS; i++) begin : gen_ways
            /* memories */
            logic             valid [SETS-1:0];
            logic [TAG_W-1:0] tags  [SETS-1:0];
            logic [     31:0] lines [SETS*LINE_WORDS-1:0];

            logic [TAG_W-1:0] tag_rdata;
            logic             valid_rdata;

            assign hit_ways[i] = valid_rdata && tag_rdata == pc_if_tag;

            always_ff @(posedge clk_i) begin
                if (update_i) begin
                    tag_rdata     <= tags[pc_d_idx];
                    valid_rdata   <= valid[pc_d_idx];
                    rdata_ways[i] <= lines[{pc_d_idx, pc_d_bo}];
                end
            end
        end : gen_ways
    endgenerate

endmodule
