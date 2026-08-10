// SPDX-License-Identifier: SHL-2.1
// SPDX-FileCopyrightText: David Schröder 2026

module nanosoc_ram
    import tilelink_pkg::*;
#(
    parameter int LOG_SIZE = 15,
    parameter string MEMFILE = ""
) (
    input  logic clk_i,
    input  logic rst_ni,

    input  tl_h2d_t tl_i,
    output tl_d2h_t tl_o
);

    reg [31:0] mem [2**(LOG_SIZE-2)-1:0];

    logic [LOG_SIZE-3:0] addr;
    logic [        31:0] wdata;
    logic                wen;
    logic [         3:0] wmask;
    logic [        31:0] rdata;

    logic       stall; // response not accepted
    logic       err_misalign;
    logic [7:0] source_q;
    tl_a_op_e   op_q;
    logic       tx_q;

    assign addr  = tl_i.a_valid ? tl_i.a_address[LOG_SIZE-1:2] : '0;
    assign wdata = tl_i.a_valid ? tl_i.a_data : '0;
    assign wen   = tl_i.a_valid
                   && tl_i.a_opcode inside {PutFullData, PutPartialData};
    assign wmask = tl_i.a_valid ? tl_i.a_mask : '0;

    assign stall = tl_o.d_valid & ~tl_i.d_ready;

    always_ff @(posedge clk_i) begin
        if (wen) begin
            if (wmask[0]) mem[addr][ 7: 0] <= wdata[ 7: 0];
            if (wmask[1]) mem[addr][15: 8] <= wdata[15: 8];
            if (wmask[2]) mem[addr][23:16] <= wdata[23:16];
            if (wmask[3]) mem[addr][31:24] <= wdata[31:24];
        end
        if (~stall) rdata <= mem[addr];
    end

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (~rst_ni) begin
            err_misalign <= '0;
            source_q <= '0;
            op_q <= Get;
            tx_q <= '0;
        end else begin
            if (~stall) begin
                tx_q <= tl_i.a_valid;
                op_q <= tl_i.a_opcode;
                err_misalign <= |tl_i.a_address[1:0];
                source_q <= tl_i.a_source;
            end
        end
    end

    assign tl_o = '{
        d_valid: tx_q,
        d_opcode: op_q == Get ? AccessAckData : AccessAck,
        d_data: rdata,
        d_denied: err_misalign,
        d_source: source_q,
        a_ready: ~stall
    };

    initial begin
        $readmemh(MEMFILE, mem);
    end

endmodule
