// SPDX-License-Identifier: SHL-2.1
// SPDX-FileCopyrightText: David Schröder 2026

module turvo32_stage_id
    import turvo32_pkg::*;
    import tilelink_pkg::*;
#(
    parameter int PASSTHROUGH_W = 2
) (
    input  logic clk_i,
    input  logic rst_ni,

    // Stage control
    input  logic ps_valid_i,
    output logic ps_ready_o,
    output logic ns_valid_o,
    input  logic ns_ready_i,
    input  logic invalidate_i,

    // Stall control (datahazards)
    input  logic        valid_mult_ex_i,
    input  logic        valid_load_ex_i,
    input  logic        valid_load_mem_i,
    input  logic        valid_csrr_ex_i,
    input  logic [ 4:0] rd_ex_i,
    input  logic [ 4:0] rd_mem_i,

    // IF inputs
    input  logic [31:0] pc_i,
    input  logic [31:0] pc_seq_i,
    input  logic [31:0] instr_i,

    // EX control signals
    output logic [ 4:0] reg_ra1_o,
    output logic [ 4:0] reg_ra2_o,
    output logic [31:0] reg_rs1_o,
    output logic [31:0] reg_rs2_o,
    output logic [31:0] imm_o,
    output logic [31:0] pc_o,
    output logic [31:0] pc_seq_o,
    output logic [31:0] instr_o,
    output alu_src1_e   alu_src1_o,
    output alu_src2_e   alu_src2_o,
    output alu_op_e     alu_op_o,
    output shift_op_e   shift_op_o,
    output branch_e     branch_o,
    output logic        is_branch_o,
    output logic        is_jump_o,
    output mult_op_e    mult_op_o,
    output div_op_e     div_op_o,
    output logic        is_mult_o,
    output logic        is_div_o,

    // MEM control signals
    output mem_op_e     mem_op_o,
    output logic        is_mem_op_o,

    // WB control signals
    output logic [ 4:0] rd_o,
    output logic        reg_we_o,
    output wb_src_e     wb_src_o,

    // Other passthrough signals
    input  logic [PASSTHROUGH_W-1:0] passthru_i,
    output logic [PASSTHROUGH_W-1:0] passthru_o,

    // Register write port
    input  logic [ 4:0] rd_i,
    input  logic [31:0] reg_wdata_i,
    input  logic        reg_we_i
);

    logic stage_ready;
    assign ps_ready_o = ns_ready_i & stage_ready;

    /////////////
    //         //
    // Signals //
    //         //
    /////////////

    logic [ 4:0] ra1;
    logic [ 4:0] ra2;

    logic        stall_mult_use;
    logic        stall_load_use;
    logic        stall_csrr_use;

    ////////////////////
    //                //
    // IF <-> ID Regs //
    //                //
    ////////////////////

    logic [31:0] pc_id;
    logic [31:0] instr_id;
    logic        valid_id;

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (~rst_ni) begin
            pc_id      <= '0;
            pc_seq_o   <= '0;
            instr_id   <= '0;
            valid_id   <= '0;
            passthru_o <= '0;
        end else begin
            if (ps_ready_o) begin
                pc_id      <= pc_i;
                pc_seq_o   <= pc_seq_i;
                instr_id   <= instr_i;
                valid_id   <= ps_valid_i;
                passthru_o <= passthru_i;
            end
        end
    end

    assign ns_valid_o = valid_id && ps_ready_o && !invalidate_i;

    /////////////////
    //             //
    // Stage Logic //
    //             //
    /////////////////

    assign pc_o = pc_id;
    assign reg_ra1_o = ra1;
    assign reg_ra2_o = ra2;

    assign stall_mult_use = valid_mult_ex_i && rd_ex_i inside {ra1, ra2};
    assign stall_load_use = valid_load_ex_i && rd_ex_i inside {ra1, ra2}
                        || valid_load_mem_i && rd_mem_i inside {ra1, ra2};
    assign stall_csrr_use = valid_csrr_ex_i && rd_ex_i inside {ra1, ra2};

    assign stage_ready = (~stall_mult_use
                      && ~stall_load_use
                      && ~stall_csrr_use)
                      || invalidate_i;

    assign instr_o = instr_id;

    ///////////////////
    //               //
    // Instantiation //
    //               //
    ///////////////////

    turvo32_decoder decoder_i (
        .instr_i  (instr_id),

        .rs1_adr_o(ra1),
        .rs2_adr_o(ra2),
        .rd_adr_o (rd_o),
        .reg_we_o (reg_we_o),

        .alu_op_o,
        .shift_op_o,
        .mem_op_o,
        .branch_o,
        .mult_op_o,
        .div_op_o,

        .is_jump_o,
        .is_branch_o,
        .is_mult_o,
        .is_div_o,
        .is_mem_op_o,

        .imm_o,
        .alu_src1_o,
        .alu_src2_o,
        .wb_src_o
    );

    turvo32_regfile regfile_i (
        .clk_i,

        .raddr1_i(ra1),
        .raddr2_i(ra2),
        .rdata1_o(reg_rs1_o),
        .rdata2_o(reg_rs2_o),
        .waddr_i (rd_i),
        .wen_i   (reg_we_i),
        .wdata_i (reg_wdata_i)
    );

endmodule
