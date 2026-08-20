// SPDX-License-Identifier: SHL-2.1
// SPDX-FileCopyrightText: David Schröder 2026

// Parameterizable 2-port SRAM for ASIC targets.
// PDK-specific: Uses IHP130-SG13G2 SRAM macros.

module prim_sram_sdp #(
    parameter  int WIDTH = 32,
    parameter  int DEPTH = 256,
    localparam int AW = $clog2(DEPTH)
) (
    input  logic             clk_i,
    input  logic             rst_ni,
    input  logic [   AW-1:0] waddr_i,
    input  logic             wen_i,
    input  logic [WIDTH-1:0] wdata_i,
    input  logic [   AW-1:0] raddr_i,
    input  logic             ren_i,
    output logic [WIDTH-1:0] rdata_o
);

    // IHP130-SG13G2 has the following dual-port SRAM macros available:
    // - RM_IHPSG13_2P_64x32_c2
    // - RM_IHPSG13_2P_256x8_c2_bm_bist
    // - RM_IHPSG13_2P_256x16_c2_bm_bist
    // - RM_IHPSG13_2P_256x32_c2_bm_bist
    // - RM_IHPSG13_2P_512x8_c2_bm_bist
    // - RM_IHPSG13_2P_512x16_c2_bm_bist
    // - RM_IHPSG13_2P_512x32_c2_bm_bist
    // - RM_IHPSG13_2P_1024x16_c2_bm_bist
    // - RM_IHPSG13_2P_1024x32_c2_bm_bist

    // The implementation strategy of this module is:
    // - select the smallest macro set with a depth > requested
    // - if requested depth > deepest macro depth, it is tiled appropriately
    // - select the smallest macro of that set with width > requested
    // - if requested width > widest macro width, it is tiled appropriately

    //////////////////////////////////////
    //                                  //
    // Common SRAM interface generation //
    //                                  //
    //////////////////////////////////////

    // The widest macros are 32 bits wide; extend all relevant interface
    // signals to a multiple of 32 bits.

    localparam int COMMONW = ((WIDTH + 31) / 32) * 32;
    localparam int MAX_AW  = DEPTH > 1024 ? $clog2(DEPTH) : 10;

    logic [ MAX_AW-1:0] waddr;
    logic [ MAX_AW-1:0] raddr;
    logic [COMMONW-1:0] wdata;
    logic [COMMONW-1:0] rdata;

    assign waddr = waddr_i;
    assign raddr = raddr_i;
    assign wdata = wdata_i;
    assign rdata_o = rdata;

    //////////////////////
    //                  //
    // Macro generation //
    //                  //
    //////////////////////

    generate

        if (DEPTH > 512) begin : gen_1024d

            logic [AW-11:0] waddr_rowsel, raddr_rowsel, raddr_rowsel_q;
            assign waddr_rowsel = waddr_i[AW-1:10];
            assign raddr_rowsel = raddr_i[AW-1:10];

            always_ff @(posedge clk_i or negedge rst_ni) begin
                if (~rst_ni) raddr_rowsel_q <= '0;
                else if (ren_i) raddr_rowsel_q <= raddr_rowsel;
            end

            localparam ROWS = (DEPTH + 1023) / 1024;
            logic [WIDTH-1:0] rdata_rows [ROWS-1:0];

            assign rdata = rdata_rows[raddr_rowsel_q];

            for (genvar row = 0; row < ROWS; row++) begin : gen_rows
                if (WIDTH > 16) begin : gen_32w
                    for (genvar i = 0; i < (WIDTH + 31) / 32; i++) begin : gen_tiles
                        RM_IHPSG13_2P_1024x32_c2_bm_bist block_i (
                            `ifdef USE_POWER_PINS
                            .VDD(vdd),
                            .VSS(vss),
                            `endif
                            .A_CLK      (clk_i),
                            .A_DIN      (wdata[32*i+:32]),
                            .A_BM       ('1),
                            .A_ADDR     (waddr),
                            .A_MEN      ('1),
                            .A_REN      ('0),
                            .A_WEN      (wen_i && waddr_rowsel == row),
                            .A_BIST_DIN ('0),
                            .A_BIST_BM  ('0),
                            .A_BIST_ADDR('0),
                            .A_BIST_WEN ('0),
                            .A_BIST_MEN ('0),
                            .A_BIST_REN ('0),
                            .A_BIST_CLK ('0),
                            .A_BIST_EN  ('0),
                            .A_DLY      ('1),
                            .A_DOUT     (),
                            .B_CLK      (clk_i),
                            .B_DIN      ('0),
                            .B_BM       ('0),
                            .B_ADDR     (raddr),
                            .B_MEN      ('1),
                            .B_REN      (ren_i && raddr_rowsel == row),
                            .B_WEN      ('0),
                            .B_BIST_DIN ('0),
                            .B_BIST_BM  ('0),
                            .B_BIST_ADDR('0),
                            .B_BIST_WEN ('0),
                            .B_BIST_MEN ('0),
                            .B_BIST_REN ('0),
                            .B_BIST_CLK ('0),
                            .B_BIST_EN  ('0),
                            .B_DLY      ('1),
                            .B_DOUT     (rdata_rows[row][32*i+:32])
                        );
                    end : gen_tiles
                end : gen_32w

                else begin : gen_16w
                    RM_IHPSG13_2P_1024x16_c2_bm_bist block_i (
                        `ifdef USE_POWER_PINS
                        .VDD(vdd),
                        .VSS(vss),
                        `endif
                        .A_CLK      (clk_i),
                        .A_DIN      (wdata[15:0]),
                        .A_BM       ('1),
                        .A_ADDR     (waddr),
                        .A_MEN      ('1),
                        .A_REN      ('0),
                        .A_WEN      (wen_i && waddr_rowsel == row),
                        .A_BIST_DIN ('0),
                        .A_BIST_BM  ('0),
                        .A_BIST_ADDR('0),
                        .A_BIST_WEN ('0),
                        .A_BIST_MEN ('0),
                        .A_BIST_REN ('0),
                        .A_BIST_CLK ('0),
                        .A_BIST_EN  ('0),
                        .A_DLY      ('1),
                        .A_DOUT     (),
                        .B_CLK      (clk_i),
                        .B_DIN      ('0),
                        .B_BM       ('0),
                        .B_ADDR     (raddr),
                        .B_MEN      ('1),
                        .B_REN      (ren_i && raddr_rowsel == row),
                        .B_WEN      ('0),
                        .B_BIST_DIN ('0),
                        .B_BIST_BM  ('0),
                        .B_BIST_ADDR('0),
                        .B_BIST_WEN ('0),
                        .B_BIST_MEN ('0),
                        .B_BIST_REN ('0),
                        .B_BIST_CLK ('0),
                        .B_BIST_EN  ('0),
                        .B_DLY      ('1),
                        .B_DOUT     (rdata_rows[i][15:0])
                    );
                end : gen_16w
            end : gen_rows

        end : gen_1024d


        else if (DEPTH > 256) begin : gen_512d

            if (WIDTH > 16) begin : gen_32w
                for (genvar i = 0; i < (WIDTH + 31) / 32; i++) begin : gen_tiles
                    RM_IHPSG13_2P_512x32_c2_bm_bist block_i (
                        `ifdef USE_POWER_PINS
                        .VDD(vdd),
                        .VSS(vss),
                        `endif
                        .A_CLK      (clk_i),
                        .A_DIN      (wdata[32*i+:32]),
                        .A_BM       ('1),
                        .A_ADDR     (waddr),
                        .A_MEN      ('1),
                        .A_REN      ('0),
                        .A_WEN      (wen_i),
                        .A_BIST_DIN ('0),
                        .A_BIST_BM  ('0),
                        .A_BIST_ADDR('0),
                        .A_BIST_WEN ('0),
                        .A_BIST_MEN ('0),
                        .A_BIST_REN ('0),
                        .A_BIST_CLK ('0),
                        .A_BIST_EN  ('0),
                        .A_DLY      ('1),
                        .A_DOUT     (),
                        .B_CLK      (clk_i),
                        .B_DIN      ('0),
                        .B_BM       ('0),
                        .B_ADDR     (raddr),
                        .B_MEN      ('1),
                        .B_REN      (ren_i),
                        .B_WEN      ('0),
                        .B_BIST_DIN ('0),
                        .B_BIST_BM  ('0),
                        .B_BIST_ADDR('0),
                        .B_BIST_WEN ('0),
                        .B_BIST_MEN ('0),
                        .B_BIST_REN ('0),
                        .B_BIST_CLK ('0),
                        .B_BIST_EN  ('0),
                        .B_DLY      ('1),
                        .B_DOUT     (rdata[32*i+:32])
                    );
                end : gen_tiles
            end : gen_32w

            else if (WIDTH > 8) begin : gen_16w
                RM_IHPSG13_2P_512x16_c2_bm_bist block_i (
                    `ifdef USE_POWER_PINS
                    .VDD(vdd),
                    .VSS(vss),
                    `endif
                    .A_CLK      (clk_i),
                    .A_DIN      (wdata[15:0]),
                    .A_BM       ('1),
                    .A_ADDR     (waddr),
                    .A_MEN      ('1),
                    .A_REN      ('0),
                    .A_WEN      (wen_i),
                    .A_BIST_DIN ('0),
                    .A_BIST_BM  ('0),
                    .A_BIST_ADDR('0),
                    .A_BIST_WEN ('0),
                    .A_BIST_MEN ('0),
                    .A_BIST_REN ('0),
                    .A_BIST_CLK ('0),
                    .A_BIST_EN  ('0),
                    .A_DLY      ('1),
                    .A_DOUT     (),
                    .B_CLK      (clk_i),
                    .B_DIN      ('0),
                    .B_BM       ('0),
                    .B_ADDR     (raddr),
                    .B_MEN      ('1),
                    .B_REN      (ren_i),
                    .B_WEN      ('0),
                    .B_BIST_DIN ('0),
                    .B_BIST_BM  ('0),
                    .B_BIST_ADDR('0),
                    .B_BIST_WEN ('0),
                    .B_BIST_MEN ('0),
                    .B_BIST_REN ('0),
                    .B_BIST_CLK ('0),
                    .B_BIST_EN  ('0),
                    .B_DLY      ('1),
                    .B_DOUT     (rdata[15:0])
                );
            end : gen_16w

            else begin : gen_8w
                RM_IHPSG13_2P_512x8_c2_bm_bist block_i (
                    `ifdef USE_POWER_PINS
                    .VDD(vdd),
                    .VSS(vss),
                    `endif
                    .A_CLK      (clk_i),
                    .A_DIN      (wdata[7:0]),
                    .A_BM       ('1),
                    .A_ADDR     (waddr),
                    .A_MEN      ('1),
                    .A_REN      ('0),
                    .A_WEN      (wen_i),
                    .A_BIST_DIN ('0),
                    .A_BIST_BM  ('0),
                    .A_BIST_ADDR('0),
                    .A_BIST_WEN ('0),
                    .A_BIST_MEN ('0),
                    .A_BIST_REN ('0),
                    .A_BIST_CLK ('0),
                    .A_BIST_EN  ('0),
                    .A_DLY      ('1),
                    .A_DOUT     (),
                    .B_CLK      (clk_i),
                    .B_DIN      ('0),
                    .B_BM       ('0),
                    .B_ADDR     (raddr),
                    .B_MEN      ('1),
                    .B_REN      (ren_i),
                    .B_WEN      ('0),
                    .B_BIST_DIN ('0),
                    .B_BIST_BM  ('0),
                    .B_BIST_ADDR('0),
                    .B_BIST_WEN ('0),
                    .B_BIST_MEN ('0),
                    .B_BIST_REN ('0),
                    .B_BIST_CLK ('0),
                    .B_BIST_EN  ('0),
                    .B_DLY      ('1),
                    .B_DOUT     (rdata[7:0])
                );
            end : gen_8w

        end : gen_512d


        else if (DEPTH > 64) begin : gen_256d

            if (WIDTH > 16) begin : gen_32w
                for (genvar i = 0; i < (WIDTH + 31) / 32; i++) begin : gen_tiles
                    RM_IHPSG13_2P_256x32_c2_bm_bist block_i (
                        `ifdef USE_POWER_PINS
                        .VDD(vdd),
                        .VSS(vss),
                        `endif
                        .A_CLK      (clk_i),
                        .A_DIN      (wdata[32*i+:32]),
                        .A_BM       ('1),
                        .A_ADDR     (waddr),
                        .A_MEN      ('1),
                        .A_REN      ('0),
                        .A_WEN      (wen_i),
                        .A_BIST_DIN ('0),
                        .A_BIST_BM  ('0),
                        .A_BIST_ADDR('0),
                        .A_BIST_WEN ('0),
                        .A_BIST_MEN ('0),
                        .A_BIST_REN ('0),
                        .A_BIST_CLK ('0),
                        .A_BIST_EN  ('0),
                        .A_DLY      ('1),
                        .A_DOUT     (),
                        .B_CLK      (clk_i),
                        .B_DIN      ('0),
                        .B_BM       ('0),
                        .B_ADDR     (raddr),
                        .B_MEN      ('1),
                        .B_REN      (ren_i),
                        .B_WEN      ('0),
                        .B_BIST_DIN ('0),
                        .B_BIST_BM  ('0),
                        .B_BIST_ADDR('0),
                        .B_BIST_WEN ('0),
                        .B_BIST_MEN ('0),
                        .B_BIST_REN ('0),
                        .B_BIST_CLK ('0),
                        .B_BIST_EN  ('0),
                        .B_DLY      ('1),
                        .B_DOUT     (rdata[32*i+:32])
                    );
                end : gen_tiles
            end : gen_32w

            else if (WIDTH > 8) begin : gen_16w
                RM_IHPSG13_2P_256x16_c2_bm_bist block_i (
                    `ifdef USE_POWER_PINS
                    .VDD(vdd),
                    .VSS(vss),
                    `endif
                    .A_CLK      (clk_i),
                    .A_DIN      (wdata[15:0]),
                    .A_BM       ('1),
                    .A_ADDR     (waddr),
                    .A_MEN      ('1),
                    .A_REN      ('0),
                    .A_WEN      (wen_i),
                    .A_BIST_DIN ('0),
                    .A_BIST_BM  ('0),
                    .A_BIST_ADDR('0),
                    .A_BIST_WEN ('0),
                    .A_BIST_MEN ('0),
                    .A_BIST_REN ('0),
                    .A_BIST_CLK ('0),
                    .A_BIST_EN  ('0),
                    .A_DLY      ('1),
                    .A_DOUT     (),
                    .B_CLK      (clk_i),
                    .B_DIN      ('0),
                    .B_BM       ('0),
                    .B_ADDR     (raddr),
                    .B_MEN      ('1),
                    .B_REN      (ren_i),
                    .B_WEN      ('0),
                    .B_BIST_DIN ('0),
                    .B_BIST_BM  ('0),
                    .B_BIST_ADDR('0),
                    .B_BIST_WEN ('0),
                    .B_BIST_MEN ('0),
                    .B_BIST_REN ('0),
                    .B_BIST_CLK ('0),
                    .B_BIST_EN  ('0),
                    .B_DLY      ('1),
                    .B_DOUT     (rdata[15:0])
                );
            end : gen_16w

            else begin : gen_8w
                RM_IHPSG13_2P_256x8_c2_bm_bist block_i (
                    `ifdef USE_POWER_PINS
                    .VDD(vdd),
                    .VSS(vss),
                    `endif
                    .A_CLK      (clk_i),
                    .A_DIN      (wdata[7:0]),
                    .A_BM       ('1),
                    .A_ADDR     (waddr),
                    .A_MEN      ('1),
                    .A_REN      ('0),
                    .A_WEN      (wen_i),
                    .A_BIST_DIN ('0),
                    .A_BIST_BM  ('0),
                    .A_BIST_ADDR('0),
                    .A_BIST_WEN ('0),
                    .A_BIST_MEN ('0),
                    .A_BIST_REN ('0),
                    .A_BIST_CLK ('0),
                    .A_BIST_EN  ('0),
                    .A_DLY      ('1),
                    .A_DOUT     (),
                    .B_CLK      (clk_i),
                    .B_DIN      ('0),
                    .B_BM       ('0),
                    .B_ADDR     (raddr),
                    .B_MEN      ('1),
                    .B_REN      (ren_i),
                    .B_WEN      ('0),
                    .B_BIST_DIN ('0),
                    .B_BIST_BM  ('0),
                    .B_BIST_ADDR('0),
                    .B_BIST_WEN ('0),
                    .B_BIST_MEN ('0),
                    .B_BIST_REN ('0),
                    .B_BIST_CLK ('0),
                    .B_BIST_EN  ('0),
                    .B_DLY      ('1),
                    .B_DOUT     (rdata[7:0])
                );
            end : gen_8w

        end : gen_256d

        else begin : gen_64d
            // There is only one 64-deep macro; tile it width-wise

            for (genvar i = 0; i < (WIDTH + 31) / 32; i++) begin : gen_tiles
                RM_IHPSG13_2P_64x32_c2 block_i (
                    .A_CLK      (clk_i),
                    .A_DIN      (wdata[32*i+:32]),
                    .A_ADDR     (waddr),
                    .A_MEN      ('1),
                    .A_REN      ('0),
                    .A_WEN      (wen_i),
                    .A_DLY      ('1),
                    .A_DOUT     (),
                    .B_CLK      (clk_i),
                    .B_DIN      ('0),
                    .B_ADDR     (raddr),
                    .B_MEN      ('1),
                    .B_REN      (ren_i),
                    .B_WEN      ('0),
                    .B_DLY      ('1),
                    .B_DOUT     (rdata[32*i+:32])
                );
            end : gen_tiles
        end : gen_64d

    endgenerate

endmodule
