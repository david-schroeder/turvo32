// SPDX-License-Identifier: SHL-2.1
// SPDX-FileCopyrightText: David Schröder 2026

module turvo32_shifter
    import turvo32_pkg::*;
(
    input  logic [31:0] data_i,
    input  logic [ 4:0] shamt_i,
    input  shift_op_e   op_i,
    output logic [31:0] data_o
);

    always_comb begin
        unique case (op_i)
            SLL: data_o = data_i << shamt_i;
            SRL: data_o = data_i >> shamt_i;
            SRA: data_o = $signed(data_i) >>> shamt_i;
            default: data_o = '0;
        endcase
    end

endmodule
