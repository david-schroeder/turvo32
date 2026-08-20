// SPDX-License-Identifier: SHL-2.1
// SPDX-FileCopyrightText: David Schröder 2026

// Parameterizable 1-port SRAM with byte-wide write enable for FPGA targets.

module prim_sram_1p_bwwe #(
    parameter  int WIDTH = 32,
    parameter  int DEPTH = 256,
    localparam int AW = $clog2(DEPTH),
    localparam int LANES = WIDTH / 8
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

    logic [WIDTH-1:0] mem [DEPTH-1:0] = '{default: '0};
    logic [WIDTH-1:0] rdata, rdata_q;
    logic             ren_q;

    always_ff @(posedge clk_i) begin
        if (wen_i) begin
            for (int i = 0; i < LANES; i++) begin
                if (wmask_i[i]) mem[addr_i][8*i+:8] <= wdata_i[8*i+:8];
            end
            rdata <= wdata_i;
        end else rdata <= mem[addr_i];
    end

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (~rst_ni) begin
            ren_q <= '0;
            rdata_q <= '0;
        end else begin
            ren_q <= ren_i;
            if (ren_q) rdata_q <= rdata;
        end
    end

    assign rdata_o = ren_q ? rdata : rdata_q;

endmodule
