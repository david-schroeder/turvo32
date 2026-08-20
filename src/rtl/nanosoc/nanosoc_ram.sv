// SPDX-License-Identifier: SHL-2.1
// SPDX-FileCopyrightText: David Schröder 2026

module nanosoc_ram
    import tilelink_pkg::*;
#(
    parameter int LOG_SIZE = 15,
    parameter logic [31:LOG_SIZE] ADDR_BASE = '0,
    parameter string MEMFILE = ""
) (
    input  logic clk_i,
    input  logic rst_ni,

    input  tl_h2d_t tl_i,
    output tl_d2h_t tl_o
);

    logic [LOG_SIZE-3:0] addr;
    logic [        31:0] wdata;
    logic                wen;
    logic [         3:0] wmask;
    logic [        31:0] rdata;

    logic       stall; // response not accepted
    logic       rsp_error, misalign_d;
    logic [7:0] source_q;
    logic [1:0] size_q;
    tl_a_op_e   op_q;
    logic       tx_q;

    assign addr  = tl_i.a_valid ? tl_i.a_address[LOG_SIZE-1:2] : '0;
    assign wdata = tl_i.a_valid ? tl_i.a_data : '0;
    assign wen   = tl_i.a_valid
                   && tl_i.a_opcode inside {PutFullData, PutPartialData};
    assign wmask = tl_i.a_valid ? tl_i.a_mask : '0;

    assign stall = tl_o.d_valid & ~tl_i.d_ready;

    generate
        for (genvar i = 0; i < 4; i++) begin : gen_byte_lanes
            prim_sram_1p #(
                .WIDTH(8),
                .DEPTH(2**(LOG_SIZE-2))
            ) byte_lane_i (
                .clk_i,
                .rst_ni,
                .addr_i (addr),
                .wen_i  (wen && wmask[i]),
                .ren_i  (~stall),
                .wdata_i(wdata[8*i+:8]),
                .rdata_o(rdata[8*i+:8])
            );
        end : gen_byte_lanes
    endgenerate

    always_comb begin
        if (tl_i.a_opcode inside {Get, PutFullData}) begin
            unique case ({tl_i.a_size, tl_i.a_mask, tl_i.a_address[1:0]})
                {2'h0, 4'b0001, 2'b00},
                {2'h0, 4'b0010, 2'b01},
                {2'h0, 4'b0100, 2'b10},
                {2'h0, 4'b1000, 2'b11},
                {2'h1, 4'b0011, 2'b00},
                {2'h1, 4'b1100, 2'b10},
                {2'h2, 4'b1111, 2'b00}: misalign_d = '0;
                default: misalign_d = '1;
            endcase
        end else begin
            // PutPartialData
            unique casez ({tl_i.a_size, tl_i.a_mask, tl_i.a_address[1:0]})
                {2'h0, 4'b000?, 2'b00},
                {2'h0, 4'b00?0, 2'b01},
                {2'h0, 4'b0?00, 2'b10},
                {2'h0, 4'b?000, 2'b11},
                {2'h1, 4'b00??, 2'b00},
                {2'h1, 4'b??00, 2'b10},
                {2'h2, 4'b????, 2'b00}: misalign_d = '0;
                default: misalign_d = '1;
            endcase
        end
    end

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (~rst_ni) begin
            rsp_error <= '0;
            source_q <= '0;
            size_q <= '0;
            op_q <= Get;
            tx_q <= '0;
        end else begin
            if (~stall) begin
                tx_q <= tl_i.a_valid;
                op_q <= tl_i.a_opcode;
                rsp_error <= misalign_d || tl_i.a_address[31:LOG_SIZE] != ADDR_BASE;
                size_q <= tl_i.a_size;
                source_q <= tl_i.a_source;
            end
        end
    end

    assign tl_o = '{
        d_valid: tx_q,
        d_opcode: op_q == Get ? AccessAckData : AccessAck,
        d_data: rdata,
        d_denied: tx_q && rsp_error,
        d_size: size_q,
        d_source: source_q,
        a_ready: ~stall
    };

    // TODO: add back memfile initialization for fpga

endmodule
