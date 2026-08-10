// SPDX-License-Identifier: SHL-2.1
// SPDX-FileCopyrightText: David Schröder 2026

// TURVo32 Load-Store Unit.
// May have exactly one outstanding memory request.
// This simplifies RISC-V spec compliance while enabling
// bus errors in the future.

module turvo32_lsu
    import turvo32_pkg::*;
    import tilelink_pkg::*;
(
    input  logic clk_i,
    input  logic rst_ni,

    input  logic [31:0] data_i,
    input  logic [31:0] address_i,
    input  logic        is_mem_op_i,
    input  mem_op_e     op_i,

    output logic [31:0] data_o,
    output logic        misaligned_o,

    input  logic        valid_i, // From MEM stage
    output logic        stall_o, // To MEM stage
    output logic        wb_stall_o, // To WB stage

    output tl_h2d_t     tl_o,
    input  tl_d2h_t     tl_i
);

    /* Common access logic */

    logic [3:0] mask;
    logic [1:0] size;
    tl_a_op_e   op;

    always_comb begin
        unique case (op_i)
            LB,
            LBU,
            SB: size = 2'h0;
            LH,
            LHU,
            SH: size = 2'h1;
            LW,
            SW: size = 2'h2;
            default: size = 2'h0;
        endcase

        unique case (op_i)
            LB,
            LBU,
            LH,
            LHU,
            LW: op = Get;
            SB,
            SH,
            SW: op = PutFullData;
            default: op = Get;
        endcase

        unique case ({op_i, address_i[1:0]})
            {SB , 2'b00}: mask = 4'b0001;
            {SB , 2'b01}: mask = 4'b0010;
            {SB , 2'b10}: mask = 4'b0100;
            {SB , 2'b11}: mask = 4'b1000;
            {SH , 2'b00}: mask = 4'b0011;
            {SH , 2'b10}: mask = 4'b1100;
            {SW , 2'b00}: mask = 4'b1111;
            {LB , 2'b00}: mask = 4'b0001;
            {LB , 2'b01}: mask = 4'b0010;
            {LB , 2'b10}: mask = 4'b0100;
            {LB , 2'b11}: mask = 4'b1000;
            {LBU, 2'b00}: mask = 4'b0001;
            {LBU, 2'b01}: mask = 4'b0010;
            {LBU, 2'b10}: mask = 4'b0100;
            {LBU, 2'b11}: mask = 4'b1000;
            {LH , 2'b00}: mask = 4'b0011;
            {LH , 2'b10}: mask = 4'b1100;
            {LHU, 2'b00}: mask = 4'b0011;
            {LHU, 2'b10}: mask = 4'b1100;
            {LW , 2'b00}: mask = 4'b1111;
            // Misaligned cases don't access memory
            default: mask = 4'b0000;
        endcase
    end

    /* Store logic */

    logic [31:0] wdata;

    always_comb begin
        unique case (op_i)
            SB: wdata = {data_i[7:0], data_i[7:0], data_i[7:0], data_i[7:0]};
            SH: wdata = {data_i[15:0], data_i[15:0]};
            default: wdata = data_i;
        endcase
    end

    /* Delayed response logic */
    // See section 4.2 of the TileLink spec v1.9.3

    tl_d2h_t bus_rsp_q, delayed_rsp;
    logic delay_rsp;

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (~rst_ni) begin
            bus_rsp_q <= '{d_opcode: AccessAck, default: '0};
            delay_rsp <= '0;
        end else begin
            bus_rsp_q <= tl_i;
            // Use bus value from registered input iff response was
            // accepted in same cycle as request was issued
            delay_rsp <= tl_o.a_valid && tl_i.d_valid && tl_o.d_ready;
        end
    end

    assign delayed_rsp = delay_rsp ? bus_rsp_q : tl_i;

    /* Bus FSM */

    typedef enum logic [0:0] {
        Idle,
        AwaitData
    } lsu_state_e;

    lsu_state_e state_d, state_q;

    logic a_exchange;
    logic d_exchange;
    logic is_valid_mem_op;
    assign a_exchange = tl_o.a_valid && tl_i.a_ready;
    assign d_exchange = delayed_rsp.d_valid; // d_ready always 1
    assign is_valid_mem_op = is_mem_op_i && valid_i && !misaligned_o;

    assign wb_stall_o = state_q == AwaitData && !d_exchange;

    always_comb begin
        unique case (state_q)
            Idle: begin
                if (is_valid_mem_op && a_exchange) begin
                    state_d = AwaitData;
                end else state_d = Idle;
                stall_o = is_valid_mem_op && !a_exchange;
            end
            AwaitData: begin
                if (d_exchange) state_d = Idle;
                else state_d = AwaitData;
                stall_o = !d_exchange || is_valid_mem_op;
            end
            default: begin
                state_d = state_q;
                stall_o = '0;
            end
        endcase
    end

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (~rst_ni) begin
            state_q <= Idle;
        end else begin
            state_q <= state_d;
        end
    end

    /* Bus interface */

    logic [31:0] rdata;
    assign rdata = delayed_rsp.d_valid ? delayed_rsp.d_data : '0;

    assign tl_o = '{
        a_valid: is_valid_mem_op && state_q == Idle,
        a_opcode: op,
        a_address: address_i,
        a_size: size,
        a_mask: mask,
        a_data: wdata,
        a_source: '0, // Only ever one outstanding request
        d_ready: '1
    };

    /* Load logic */

    mem_op_e     op_q;
    logic [ 1:0] offset_q;
    logic [15:0] sel_halfword;
    logic [ 7:0] sel_byte;

    assign sel_halfword = offset_q[1] ? rdata[31:16] : rdata[15:0];
    assign sel_byte = offset_q[0] ? sel_halfword[15:8] : sel_halfword[7:0];

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (~rst_ni) begin
            op_q <= LB;
            offset_q <= '0;
        end else begin
            if (state_q == Idle) begin
                op_q <= op_i;
                offset_q <= address_i[1:0];
            end
        end
    end

    always_comb begin
        unique case (op_q)
            LB : data_o = {{24{sel_byte[7]}}, sel_byte};
            LBU: data_o = {24'h0, sel_byte};
            LH : data_o = {{16{sel_halfword[15]}}, sel_halfword};
            LHU: data_o = {16'h0, sel_halfword};
            default: data_o = rdata;
        endcase
    end

    /* Misalignment logic */

    always_comb begin
        unique case ({op_i, address_i[1:0]})
            {LH , 2'b01},
            {LHU, 2'b01},
            {LH , 2'b11},
            {LHU, 2'b11},
            {LW , 2'b01},
            {LW , 2'b10},
            {LW , 2'b11},
            {SH , 2'b01},
            {SH , 2'b11},
            {SW , 2'b01},
            {SW , 2'b10},
            {SW , 2'b11}: misaligned_o = '1;
            default: misaligned_o = '0;
        endcase
    end

endmodule
