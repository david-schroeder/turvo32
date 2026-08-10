// SPDX-License-Identifier: SHL-2.1
// SPDX-FileCopyrightText: David Schröder 2026

module turvo32_trap
    import turvo32_pkg::*;
(
    input  logic clk_i,
    input  logic rst_ni,

    // External interrupt source
    input  logic [31:0] ext_ints_i,

    input  logic [31:0] pc_i,
    input  logic [31:0] next_arch_pc_i,
    input  logic        instr_valid_i,
    input  logic        stall_i,

    // CSR sources
    input  mstatus_t    mstatus_i,
    input  logic [31:0] mie_i,
    input  logic [31:0] mip_i,
    input  mtvec_t      mtvec_i,

    // Exception causes
    input  logic        ecall_i,
    input  logic        ebreak_i,
    input  logic        mem_misaligned_i,
    input  logic        mem_bus_err_i,
    input  mem_op_e     mem_op_i,
    input  logic [31:0] mem_addr_i,

    // Output
    output logic        trap_o,
    output mcause_t     cause_o,
    output logic [31:0] trap_pc_o,
    output logic [31:0] trap_val_o,
    output logic [31:0] epc_o
);

    logic [31:0] pending_ints;
    logic [31:0] valid_ints;
    logic        valid_int_q;
    mcause_t     interrupt_cause_q;
    logic        interrupt;

    logic [31:0] next_arch_pc_q;
    logic [31:0] current_pc_q;
    logic [31:0] mem_addr_q;
    mem_op_e     mem_op_q;
    logic [31:0] next_arch_pc;
    logic [31:0] current_pc;

    assign next_arch_pc = instr_valid_i ? next_arch_pc_i : next_arch_pc_q;
    assign current_pc = instr_valid_i ? pc_i : current_pc_q;

    assign pending_ints = mip_i | ext_ints_i;
    assign valid_ints   = mie_i & pending_ints;
    assign interrupt    = ~stall_i & valid_int_q & {32{mstatus_i.mie}};

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (~rst_ni) begin
            valid_int_q <= '0;
            interrupt_cause_q <= '{interrupt: '1, cause: exc_cause_e'('0)};
            next_arch_pc_q <= '0;
            current_pc_q <= '0;
            mem_addr_q <= '0;
            mem_op_q <= LB;
        end else begin
            valid_int_q <= |valid_ints;
            for (int i = 0; i < 32; i++) begin
                if (valid_ints[i]) interrupt_cause_q.cause <= exc_cause_e'(i);
            end
            if (instr_valid_i) begin
                next_arch_pc_q <= next_arch_pc_i;
                current_pc_q <= pc_i;
                mem_addr_q <= mem_addr_i;
                mem_op_q <= mem_op_i;
            end
        end
    end

    logic exception;
    assign exception = ecall_i | ebreak_i | mem_misaligned_i | mem_bus_err_i;

    assign trap_o = interrupt | exception;

    always_comb begin
        cause_o = '{cause: exc_cause_e'('0), default: '0};
        trap_val_o = '0;
        epc_o = next_arch_pc;

        if (interrupt && !exception) begin
            cause_o = interrupt_cause_q;
        end

        trap_pc_o = mtvec_i.mode && interrupt && !exception
                    ? {mtvec_i.base + 5'(interrupt_cause_q.cause), 2'b00}
                    : {mtvec_i.base, 2'b00};

        if (exception) begin
            priority case (1'b1)
                ecall_i: cause_o.cause = ECALL_MMODE;
                ebreak_i: cause_o.cause = BREAKPOINT;
                mem_misaligned_i: begin
                    unique case (mem_op_i)
                        SB,
                        SH,
                        SW: cause_o.cause = STORE_ADDR_MISALIGNED;
                        default: cause_o.cause = LOAD_ADDR_MISALIGNED;
                    endcase

                    trap_val_o = mem_addr_i;
                end
                mem_bus_err_i: begin
                    unique case (mem_op_q)
                        SB,
                        SH,
                        SW: cause_o.cause = STORE_ACCESS_FAULT;
                        default: cause_o.cause = LOAD_ACCESS_FAULT;
                    endcase

                    trap_val_o = mem_addr_q;
                end
            endcase

            epc_o = mem_bus_err_i ? current_pc_q : current_pc;
        end

    end

endmodule
