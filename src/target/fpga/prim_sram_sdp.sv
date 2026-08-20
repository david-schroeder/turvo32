// SPDX-License-Identifier: SHL-2.1
// SPDX-FileCopyrightText: David Schröder 2026

// Parameterizable 2-port SRAM for FPGA targets.

module prim_sram_sdp #(
    parameter  int WIDTH = 32,
    parameter  int DEPTH = 256,
    localparam int AW = $clog2(DEPTH)
) (
    input  logic             clk_i,
    input  logic [   AW-1:0] waddr_i,
    input  logic             wen_i,
    input  logic [WIDTH-1:0] wdata_i,
    input  logic [   AW-1:0] raddr_i,
    input  logic             ren_i,
    output logic [WIDTH-1:0] rdata_o
);

    logic [WIDTH-1:0] mem [DEPTH-1:0];

    always_ff @(posedge clk_i) begin
        if (wen_i) mem[waddr_i] <= wdata_i;
        if (ren_i) rdata_o <= mem[raddr_i];
    end
endmodule
