// SPDX-License-Identifier: SHL-2.1
// SPDX-FileCopyrightText: David Schröder 2026

// Parameterizable 1-port SRAM with byte-wide write enable for ASIC targets.
// PDK-specific: Uses IHP130-SG13G2 SRAM macros.

module prim_sram_1p_bwwe #(
    parameter  int WIDTH = 32,
    parameter  int DEPTH = 65536,
    localparam int AW = $clog2(DEPTH),
    localparam int LANES = (WIDTH + 7) / 8
) (
    input  logic             clk_i,
    input  logic             rst_ni,
    input  logic [   AW-1:0] addr_i,
    input  logic             wen_i,
    input  logic [LANES-1:0] wmask_i,
    input  logic             ren_i,
    input  logic [WIDTH-1:0] wdata_i,
    output logic [WIDTH-1:0] rdata_o
);

    // IHP130-SG13G2 has the following bitmasked single-port macros available:
    // - RM_IHPSG13_1P_64x64_c2_bm_bist
    // - RM_IHPSG13_1P_256x8_c3_bm_bist
    // - RM_IHPSG13_1P_256x16_c2_bm_bist
    // - RM_IHPSG13_1P_256x32_c2_bm_bist
    // - RM_IHPSG13_1P_256x48_c2_bm_bist
    // - RM_IHPSG13_1P_256x64_c2_bm_bist
    // - RM_IHPSG13_1P_512x8_c3_bm_bist
    // - RM_IHPSG13_1P_512x16_c2_bm_bist
    // - RM_IHPSG13_1P_512x32_c2_bm_bist
    // - RM_IHPSG13_1P_512x64_c2_bm_bist
    // - RM_IHPSG13_1P_1024x8_c2_bm_bist
    // - RM_IHPSG13_1P_1024x16_c2_bm_bist
    // - RM_IHPSG13_1P_1024x32_c2_bm_bist
    // - RM_IHPSG13_1P_1024x64_c2_bm_bist
    // - RM_IHPSG13_1P_2048x32_c2_bm_bist
    // - RM_IHPSG13_1P_2048x64_c2_bm_bist
    // - RM_IHPSG13_1P_4096x8_c3_bm_bist
    // - RM_IHPSG13_1P_4096x16_c3_bm_bist

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

    logic [8*LANES-1:0] bitmask;

    generate
        for (genvar i = 0; i < LANES; i++) begin : gen_bm_bytes
            assign bitmask[8*i+:8] = {8{wmask_i[i]}};
        end : gen_bm_bytes
    endgenerate

    // The widest macros are 64 bits wide; extend all relevant interface
    // signals to a multiple of 64 bits.

    localparam int COMMONW = ((WIDTH + 63) / 64) * 64;
    localparam int MAX_AW  = DEPTH > 4096 ? $clog2(DEPTH) : 12;

    logic [COMMONW-1:0] wmask;
    logic [COMMONW-1:0] wdata;
    logic [COMMONW-1:0] rdata;
    logic [ MAX_AW-1:0] address;

    assign wmask = bitmask;
    assign wdata = wdata_i;
    assign rdata_o = rdata;
    assign address = addr_i;

    //////////////////////
    //                  //
    // Macro generation //
    //                  //
    //////////////////////

    generate

        if (DEPTH > 2048) begin : gen_4096d

            logic [AW-13:0] addr_rowsel, addr_rowsel_q;
            assign addr_rowsel = addr_i[AW-1:12];

            always_ff @(posedge clk_i or negedge rst_ni) begin
                if (~rst_ni) addr_rowsel_q <= '0;
                else if (ren_i) addr_rowsel_q <= addr_rowsel;
            end

            localparam ROWS = (DEPTH + 4095) / 4096;
            logic [WIDTH-1:0] rdata_rows [ROWS-1:0];

            assign rdata = rdata_rows[addr_rowsel_q];

            for (genvar row = 0; row < ROWS; row++) begin : gen_rows
                if (WIDTH > 8) begin : gen_16w
                    for (genvar i = 0; i < (WIDTH + 15) / 16; i++) begin : gen_tiles
                        RM_IHPSG13_1P_4096x16_c3_bm_bist block_i (
                            .POWER_PIN_GUARD(),
                            .A_CLK      (clk_i),
                            .A_DIN      (wdata[16*i+:16]),
                            .A_BM       (wmask[16*i+:16]),
                            .A_ADDR     (address),
                            .A_MEN      ('1),
                            .A_REN      (ren_i && addr_rowsel == row),
                            .A_WEN      (wen_i && addr_rowsel == row),
                            .A_BIST_DIN ('0),
                            .A_BIST_BM  ('0),
                            .A_BIST_ADDR('0),
                            .A_BIST_WEN ('0),
                            .A_BIST_MEN ('0),
                            .A_BIST_REN ('0),
                            .A_BIST_CLK ('0),
                            .A_BIST_EN  ('0),
                            .A_DLY      ('1),
                            .A_DOUT     (rdata_rows[row][16*i+:16])
                        );
                    end : gen_tiles
                end : gen_16w

                else begin : gen_8w
                    RM_IHPSG13_1P_4096x8_c3_bm_bist block_i (
                        .POWER_PIN_GUARD(),
                        .A_CLK      (clk_i),
                        .A_DIN      (wdata[7:0]),
                        .A_BM       (wmask[7:0]),
                        .A_ADDR     (address),
                        .A_MEN      ('1),
                        .A_REN      (ren_i && addr_rowsel == row),
                        .A_WEN      (wen_i && addr_rowsel == row),
                        .A_BIST_DIN ('0),
                        .A_BIST_BM  ('0),
                        .A_BIST_ADDR('0),
                        .A_BIST_WEN ('0),
                        .A_BIST_MEN ('0),
                        .A_BIST_REN ('0),
                        .A_BIST_CLK ('0),
                        .A_BIST_EN  ('0),
                        .A_DLY      ('1),
                        .A_DOUT     (rdata_rows[row][7:0])
                    );
                end : gen_8w
            end : gen_rows

        end : gen_4096d


        else if (DEPTH > 1024) begin : gen_2048d

            if (WIDTH > 32) begin : gen_64w
                for (genvar i = 0; i < (WIDTH + 63) / 64; i++) begin : gen_tiles
                    RM_IHPSG13_1P_2048x64_c2_bm_bist block_i (
                        .POWER_PIN_GUARD(),
                        .A_CLK      (clk_i),
                        .A_DIN      (wdata[64*i+:64]),
                        .A_BM       (wmask[64*i+:64]),
                        .A_ADDR     (address),
                        .A_MEN      ('1),
                        .A_REN      (ren_i),
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
                        .A_DOUT     (rdata[64*i+:64])
                    );
                end : gen_tiles
            end : gen_64w

            else begin : gen_32w
                RM_IHPSG13_1P_2048x32_c2_bm_bist block_i (
                    .POWER_PIN_GUARD(),
                    .A_CLK      (clk_i),
                    .A_DIN      (wdata[31:0]),
                    .A_BM       (wmask[31:0]),
                    .A_ADDR     (address),
                    .A_MEN      ('1),
                    .A_REN      (ren_i),
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
                    .A_DOUT     (rdata[31:0])
                );
            end : gen_32w
        end : gen_2048d


        else if (DEPTH > 512) begin : gen_1024d

            if (WIDTH > 32) begin : gen_64w
                for (genvar i = 0; i < (WIDTH + 63) / 64; i++) begin : gen_tiles
                    RM_IHPSG13_1P_1024x64_c2_bm_bist block_i (
                        .POWER_PIN_GUARD(),
                        .A_CLK      (clk_i),
                        .A_DIN      (wdata[64*i+:64]),
                        .A_BM       (wmask[64*i+:64]),
                        .A_ADDR     (address),
                        .A_MEN      ('1),
                        .A_REN      (ren_i),
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
                        .A_DOUT     (rdata[64*i+:64])
                    );
                end : gen_tiles
            end : gen_64w

            else if (WIDTH > 16) begin : gen_32w
                RM_IHPSG13_1P_1024x32_c2_bm_bist block_i (
                    .POWER_PIN_GUARD(),
                    .A_CLK      (clk_i),
                    .A_DIN      (wdata[31:0]),
                    .A_BM       (wmask[31:0]),
                    .A_ADDR     (address),
                    .A_MEN      ('1),
                    .A_REN      (ren_i),
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
                    .A_DOUT     (rdata[31:0])
                );
            end : gen_32w

            else if (WIDTH > 8) begin : gen_16w
                RM_IHPSG13_1P_1024x16_c2_bm_bist block_i (
                    .POWER_PIN_GUARD(),
                    .A_CLK      (clk_i),
                    .A_DIN      (wdata[15:0]),
                    .A_BM       (wmask[15:0]),
                    .A_ADDR     (address),
                    .A_MEN      ('1),
                    .A_REN      (ren_i),
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
                    .A_DOUT     (rdata[15:0])
                );
            end : gen_16w

            else begin : gen_8w
                RM_IHPSG13_1P_1024x8_c2_bm_bist block_i (
                    .POWER_PIN_GUARD(),
                    .A_CLK      (clk_i),
                    .A_DIN      (wdata[7:0]),
                    .A_BM       (wmask[7:0]),
                    .A_ADDR     (address),
                    .A_MEN      ('1),
                    .A_REN      (ren_i),
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
                    .A_DOUT     (rdata[7:0])
                );
            end : gen_8w

        end : gen_1024d


        else if (DEPTH > 256) begin : gen_512d

            if (WIDTH > 32) begin : gen_64w
                for (genvar i = 0; i < (WIDTH + 63) / 64; i++) begin : gen_tiles
                    RM_IHPSG13_1P_512x64_c2_bm_bist block_i (
                        .POWER_PIN_GUARD(),
                        .A_CLK      (clk_i),
                        .A_DIN      (wdata[64*i+:64]),
                        .A_BM       (wmask[64*i+:64]),
                        .A_ADDR     (address),
                        .A_MEN      ('1),
                        .A_REN      (ren_i),
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
                        .A_DOUT     (rdata[64*i+:64])
                    );
                end : gen_tiles
            end : gen_64w

            else if (WIDTH > 16) begin : gen_32w
                RM_IHPSG13_1P_512x32_c2_bm_bist block_i (
                    .POWER_PIN_GUARD(),
                    .A_CLK      (clk_i),
                    .A_DIN      (wdata[31:0]),
                    .A_BM       (wmask[31:0]),
                    .A_ADDR     (address),
                    .A_MEN      ('1),
                    .A_REN      (ren_i),
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
                    .A_DOUT     (rdata[31:0])
                );
            end : gen_32w

            else if (WIDTH > 8) begin : gen_16w
                RM_IHPSG13_1P_512x16_c2_bm_bist block_i (
                    .POWER_PIN_GUARD(),
                    .A_CLK      (clk_i),
                    .A_DIN      (wdata[15:0]),
                    .A_BM       (wmask[15:0]),
                    .A_ADDR     (address),
                    .A_MEN      ('1),
                    .A_REN      (ren_i),
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
                    .A_DOUT     (rdata[15:0])
                );
            end : gen_16w

            else begin : gen_8w
                RM_IHPSG13_1P_512x8_c3_bm_bist block_i (
                    .POWER_PIN_GUARD(),
                    .A_CLK      (clk_i),
                    .A_DIN      (wdata[7:0]),
                    .A_BM       (wmask[7:0]),
                    .A_ADDR     (address),
                    .A_MEN      ('1),
                    .A_REN      (ren_i),
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
                    .A_DOUT     (rdata[7:0])
                );
            end : gen_8w

        end : gen_512d


        else if (DEPTH > 64) begin : gen_256d

            if (WIDTH > 48) begin : gen_64w
                for (genvar i = 0; i < (WIDTH + 63) / 64; i++) begin : gen_tiles
                    RM_IHPSG13_1P_256x64_c2_bm_bist block_i (
                        .POWER_PIN_GUARD(),
                        .A_CLK      (clk_i),
                        .A_DIN      (wdata[64*i+:64]),
                        .A_BM       (wmask[64*i+:64]),
                        .A_ADDR     (address),
                        .A_MEN      ('1),
                        .A_REN      (ren_i),
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
                        .A_DOUT     (rdata[64*i+:64])
                    );
                end : gen_tiles
            end : gen_64w

            else if (WIDTH > 32) begin : gen_48w
                RM_IHPSG13_1P_256x48_c2_bm_bist block_i (
                    .POWER_PIN_GUARD(),
                    .A_CLK      (clk_i),
                    .A_DIN      (wdata[47:0]),
                    .A_BM       (wmask[47:0]),
                    .A_ADDR     (address),
                    .A_MEN      ('1),
                    .A_REN      (ren_i),
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
                    .A_DOUT     (rdata[47:0])
                );
            end : gen_48w

            else if (WIDTH > 16) begin : gen_32w
                RM_IHPSG13_1P_256x32_c2_bm_bist block_i (
                    .POWER_PIN_GUARD(),
                    .A_CLK      (clk_i),
                    .A_DIN      (wdata[31:0]),
                    .A_BM       (wmask[31:0]),
                    .A_ADDR     (address),
                    .A_MEN      ('1),
                    .A_REN      (ren_i),
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
                    .A_DOUT     (rdata[31:0])
                );
            end : gen_32w

            else if (WIDTH > 8) begin : gen_16w
                RM_IHPSG13_1P_256x16_c2_bm_bist block_i (
                    .POWER_PIN_GUARD(),
                    .A_CLK      (clk_i),
                    .A_DIN      (wdata[15:0]),
                    .A_BM       (wmask[15:0]),
                    .A_ADDR     (address),
                    .A_MEN      ('1),
                    .A_REN      (ren_i),
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
                    .A_DOUT     (rdata[15:0])
                );
            end : gen_16w

            else begin : gen_8w
                RM_IHPSG13_1P_256x8_c3_bm_bist block_i (
                    .POWER_PIN_GUARD(),
                    .A_CLK      (clk_i),
                    .A_DIN      (wdata[7:0]),
                    .A_BM       (wmask[7:0]),
                    .A_ADDR     (address),
                    .A_MEN      ('1),
                    .A_REN      (ren_i),
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
                    .A_DOUT     (rdata[7:0])
                );
            end : gen_8w

        end : gen_256d


        else begin : gen_64d
            // There is only one 64-deep macro; tile it width-wise

            for (genvar i = 0; i < (WIDTH + 63) / 64; i++) begin : gen_tiles
                RM_IHPSG13_1P_64x64_c2_bm_bist block_i (
                    .POWER_PIN_GUARD(),
                    .A_CLK      (clk_i),
                    .A_DIN      (wdata[64*i+:64]),
                    .A_BM       (wmask[64*i+:64]),
                    .A_ADDR     (address),
                    .A_MEN      ('1),
                    .A_REN      (ren_i),
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
                    .A_DOUT     (rdata[64*i+:64])
                );
            end : gen_tiles
        end : gen_64d

    endgenerate

endmodule
