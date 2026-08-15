// SPDX-License-Identifier: SHL-2.1
// SPDX-FileCopyrightText: David Schröder 2026

module turvo32_divider
    import turvo32_pkg::*;
(
    input  logic clk_i,
    input  logic rst_ni,

    input  logic [31:0] rs1_i,
    input  logic [31:0] rs2_i,
    output logic [31:0] result_o,

    input  div_op_e     op_i,
    input  logic        is_div_i,
    output logic        div_stall_o
);

    /* Divider */

    logic        div_active;
    logic        div_start;
    logic        div_finish;
    logic        fast_div;
    logic        div_signed;
    logic        quot_sign, rem_sign;
    logic [ 4:0] div_shifts_remaining;
    logic [31:0] numerator, numerator_d;
    logic [31:0] denominator;
    logic [31:0] quotient, quotient_d;
    logic [31:0] remainder, remainder_d;
    logic [31:0] result_quotient;
    logic [31:0] result_remainder;
    logic [31:0] signed_quot, signed_rem;
    logic [31:0] rem_shifted;
    logic        skip_subtraction;

    always_comb begin
        unique case (op_i)
            DIV,
            DIVU,
            REM,
            REMU: div_start = is_div_i; // TODO: revise? this seems trivial
            default: div_start = '0;
        endcase
    end

    assign div_signed = op_i == DIV || op_i == REM;
    assign numerator_d = div_signed && rs1_i[31] ? -rs1_i : rs1_i;
    assign fast_div = numerator_d[31:16] == '0;
    assign quot_sign = rs1_i[31] ^ rs2_i[31];
    assign rem_sign = rs1_i[31];

    assign rem_shifted = {remainder[30:0], numerator[div_shifts_remaining]};
    assign skip_subtraction = rem_shifted < denominator;
    assign remainder_d = skip_subtraction ? rem_shifted : rem_shifted - denominator;
    assign quotient_d = {quotient[30:0], ~skip_subtraction};

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (~rst_ni) begin
            div_active           <= '0;
            div_shifts_remaining <= '1; // 31
            numerator            <= '0;
            denominator          <= '0;
            quotient             <= '0;
            remainder            <= '0;
            result_quotient      <= '0;
            result_remainder     <= '0;
        end else begin
            if (div_start) begin
                div_active  <= ~div_finish;
                numerator   <= numerator_d;
                denominator <= div_signed && rs2_i[31] ? -rs2_i : rs2_i;

                div_shifts_remaining <= fast_div ? 5'h0F : 5'h1F;
            end

            if (div_active) begin
                remainder            <= remainder_d;
                quotient             <= quotient_d;
                div_active           <= ~div_finish;
                div_shifts_remaining <= div_shifts_remaining - 1;
            end

            if (div_finish) begin
                result_quotient <= quotient_d;
                result_remainder <= remainder_d;
                remainder <= '0;
                quotient <= '0;
                if (div_active) div_shifts_remaining <= '0;
            end
        end
    end

    assign div_finish = div_shifts_remaining == '0;
    assign div_stall_o = div_start & ~div_finish | div_active;
    assign signed_quot = quot_sign ? -result_quotient : result_quotient;
    assign signed_rem = rem_sign ? -result_remainder : result_remainder;

    /* Result mux */
    always_comb begin
        unique case (op_i)
            DIV: result_o = signed_quot;
            DIVU: result_o = result_quotient;
            REM: result_o = signed_rem;
            REMU: result_o = result_remainder;
            default: result_o = '0;
        endcase
    end

endmodule
