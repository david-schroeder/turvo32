// SPDX-License-Identifier: SHL-2.1
// SPDX-FileCopyrightText: David Schröder 2026

module turvo32_alu
    import turvo32_pkg::*;
(
    input  logic [31:0] a_i,
    input  logic [31:0] b_i,
    input  alu_op_e     op_i,
    output logic [31:0] res_o,
    input  branch_e     branch_i,
    output logic        take_branch_o
);

    logic lt, ltu, eq;
    assign lt  = $signed(a_i) < $signed(b_i);
    assign ltu = a_i < b_i;
    assign eq = a_i == b_i;

    always_comb begin
        unique case (op_i)
            SUB : res_o = a_i - b_i;
            XOR : res_o = a_i ^ b_i;
            OR  : res_o = a_i | b_i;
            AND : res_o = a_i & b_i;
            SLT : res_o = {31'h0, lt};
            SLTU: res_o = {31'h0, ltu};
            default: res_o = a_i + b_i;
        endcase

        unique case (branch_i)
            BEQ : take_branch_o = eq;
            BNE : take_branch_o = ~eq;
            BLT : take_branch_o = lt;
            BGE : take_branch_o = ~lt;
            BLTU: take_branch_o = ltu;
            BGEU: take_branch_o = ~ltu;
            default: take_branch_o = '0;
        endcase
    end

endmodule
