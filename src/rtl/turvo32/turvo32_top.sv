// SPDX-License-Identifier: SHL-2.1
// SPDX-FileCopyrightText: David Schröder 2026

module turvo32_top
    import turvo32_pkg::*;
    import tilelink_pkg::*;
#(
    // Hard entrypoints
    parameter  logic [31:0] BOOT_ADDR      = 32'h00000080,
    parameter  logic [31:0] DEBUG_ADDR     = 32'h10000000,
    parameter  logic [31:0] DEBUG_EXC_ADDR = 32'h10001000,

    // Component parameterization

    parameter  int BTB_SETS = 256,
    parameter  int BTB_WAYS = 4
) (
    input  logic clk_i,
    input  logic rst_ni,

    input  logic [31:0] interrupts_i,

    output tl_h2d_t     ibus_o,
    input  tl_d2h_t     ibus_i,
    output tl_h2d_t     dbus_o,
    input  tl_d2h_t     dbus_i
);

    // Stage control signals
    logic if_stage_valid;
    logic id_stage_valid;
    logic ex_stage_valid;
    logic mem_stage_valid;

    logic id_stage_ready;
    logic ex_stage_ready;
    logic mem_stage_ready;
    // WB stage must always be ready

    // IF stage signals
    localparam int BTB_WAYW = $clog2(BTB_WAYS);
    logic [BTB_WAYW-1:0] btb_way_if;
    logic [        31:0] pc_if;
    logic [        31:0] pc_seq_if;
    logic [        31:0] instr_if;

    // ID stage signals
    logic [        31:0] pc_id;
    logic [        31:0] pc_seq_id;
    logic [        31:0] instr_id;
    logic [         4:0] ra1_id;
    logic [         4:0] ra2_id;
    logic [        31:0] rs1_id;
    logic [        31:0] rs2_id;
    logic [        31:0] imm_id;
    alu_src1_e           alu_src1_id;
    alu_src2_e           alu_src2_id;
    alu_op_e             alu_op_id;
    shift_op_e           shift_op_id;
    branch_e             branch_type_id;
    logic                is_branch_id;
    logic                is_jump_id;
    mult_op_e            mult_op_id;
    div_op_e             div_op_id;
    logic                is_mult_id;
    logic                is_div_id;
    mem_op_e             mem_op_id;
    logic                is_mem_op_id;
    logic [         4:0] rd_id;
    logic                reg_we_id;
    wb_src_e             wb_src_id;

    // EX stage signals
    logic [        31:0] pc_ex;
    logic [        31:0] seq_pc_ex;
    logic [        31:0] instr_ex;
    logic [        31:0] rs1_ex;
    logic [        31:0] jump_target_ex;
    logic [        31:0] branch_target_ex;
    logic                is_branch_ex;
    logic                is_jump_ex;
    logic                is_valid_mult_ex;
    logic                is_valid_load_ex;
    logic                is_valid_csrr_ex;
    logic                take_branch_ex;
    mem_op_e             mem_op_ex;
    logic                is_mem_op_ex;
    logic [        31:0] mem_wdata_ex;
    logic [         4:0] rd_ex;
    logic                reg_we_ex;
    wb_src_e             wb_src_ex;
    logic [        31:0] result_ex;
    logic [        31:0] mult_result_ex;

    // MEM stage signals
    logic [         4:0] rd_mem;
    logic                reg_we_mem;
    wb_src_e             wb_src_mem;
    logic [        31:0] reg_wdata_mem;
    logic [        31:0] lsu_rdata_mem;
    logic [        31:0] jump_tgt_mem;
    logic                do_jump_mem;
    logic                is_valid_load_mem;
    logic                inval_if_mem;
    logic                inval_id_mem;
    logic                inval_ex_mem;
    logic                fw_valid_mem;
    logic [         4:0] fw_rd_mem;
    logic [        31:0] fw_data_mem;
    logic [        31:0] btb_pc_mem;
    logic [        31:0] btb_tgt_mem;
    logic                btb_cond_mem;
    logic                btb_we_mem;

    // WB stage signals
    logic [         4:0] rd_wb;
    logic                reg_we_wb;
    logic [        31:0] reg_wdata_wb;
    logic                fw_valid_wb;
    logic [         4:0] fw_rd_wb;
    logic [        31:0] fw_data_wb;

    /////////////////////////
    //                     //
    // Stage Instantiation //
    //                     //
    /////////////////////////

    turvo32_stage_if #(
        .BOOT_ADDR     (BOOT_ADDR),
        .DEBUG_ADDR    (DEBUG_ADDR),
        .DEBUG_EXC_ADDR(DEBUG_EXC_ADDR)
    ) if_stage_i (
        .clk_i,
        .rst_ni,

        .ns_ready_i  (id_stage_ready),
        .ns_valid_o  (if_stage_valid),
        .invalidate_i(inval_if_mem),

        .jump_tgt_i(jump_tgt_mem),
        .do_jump_i (do_jump_mem),

        .pc_o    (pc_if),
        .pc_seq_o(pc_seq_if),
        .instr_o (instr_if),

        .btb_way_o   (btb_way_if),
        .btb_way_i   ('0),
        .btb_pc_i    (btb_pc_mem),
        .btb_tgt_i   (btb_tgt_mem),
        .btb_cond_i  (btb_cond_mem),
        .btb_we_i    (btb_we_mem),

        .ibus_o,
        .ibus_i
    );

    turvo32_stage_id id_stage_i (
        .clk_i,
        .rst_ni,

        .ps_valid_i  (if_stage_valid),
        .ps_ready_o  (id_stage_ready),
        .ns_valid_o  (id_stage_valid),
        .ns_ready_i  (ex_stage_ready),
        .invalidate_i(inval_id_mem),

        .valid_mult_ex_i (is_valid_mult_ex),
        .valid_load_ex_i (is_valid_load_ex),
        .valid_load_mem_i(is_valid_load_mem),
        .valid_csrr_ex_i (is_valid_csrr_ex),
        .rd_ex_i         (rd_ex),
        .rd_mem_i        (rd_mem),

        .pc_i        (pc_if),
        .pc_seq_i    (pc_seq_if),
        .instr_i     (instr_if),
    
        .reg_ra1_o   (ra1_id),
        .reg_ra2_o   (ra2_id),
        .reg_rs1_o   (rs1_id),
        .reg_rs2_o   (rs2_id),
        .imm_o       (imm_id),
        .pc_o        (pc_id),
        .pc_seq_o    (pc_seq_id),
        .instr_o     (instr_id),
        .alu_src1_o  (alu_src1_id),
        .alu_src2_o  (alu_src2_id),
        .alu_op_o    (alu_op_id),
        .shift_op_o  (shift_op_id),
        .branch_o    (branch_type_id),
        .is_branch_o (is_branch_id),
        .is_jump_o   (is_jump_id),
        .mult_op_o   (mult_op_id),
        .div_op_o    (div_op_id),
        .is_mult_o   (is_mult_id),
        .is_div_o    (is_div_id),
        .mem_op_o    (mem_op_id),
        .is_mem_op_o (is_mem_op_id),

        .rd_o    (rd_id),
        .reg_we_o(reg_we_id),
        .wb_src_o(wb_src_id),

        .rd_i       (rd_wb),
        .reg_wdata_i(reg_wdata_wb),
        .reg_we_i   (reg_we_wb)
    );

    turvo32_stage_ex ex_stage_i (
        .clk_i,
        .rst_ni,

        .ps_valid_i  (id_stage_valid),
        .ps_ready_o  (ex_stage_ready),
        .ns_valid_o  (ex_stage_valid),
        .ns_ready_i  (mem_stage_ready),
        .invalidate_i(inval_ex_mem),

        .pc_i       (pc_id),
        .pc_seq_i   (pc_seq_id),
        .instr_i    (instr_id),
        .ra1_i      (ra1_id),
        .ra2_i      (ra2_id),
        .rs1_i      (rs1_id),
        .rs2_i      (rs2_id),
        .imm_i      (imm_id),
        .alu_src1_i (alu_src1_id),
        .alu_src2_i (alu_src2_id),
        .alu_op_i   (alu_op_id),
        .shift_op_i (shift_op_id),
        .branch_i   (branch_type_id),
        .is_branch_i(is_branch_id),
        .is_jump_i  (is_jump_id),
        .mult_op_i  (mult_op_id),
        .is_mult_i  (is_mult_id),
        .div_op_i   (div_op_id),
        .is_div_i   (is_div_id),
        .mem_op_i   (mem_op_id),
        .is_mem_op_i(is_mem_op_id),
        .rd_i       (rd_id),
        .reg_we_i   (reg_we_id),
        .wb_src_i   (wb_src_id),

        .is_valid_mult_o(is_valid_mult_ex),
        .is_valid_load_o(is_valid_load_ex),
        .is_valid_csrr_o(is_valid_csrr_ex),

        .ce_mem_i(mem_stage_ready),
        .ce_wb_i ('1),

        .jump_target_o  (jump_target_ex),
        .branch_target_o(branch_target_ex),
        .is_branch_o    (is_branch_ex),
        .is_jump_o      (is_jump_ex),
        .take_branch_o  (take_branch_ex),

        .fw_valid_mem_i(fw_valid_mem),
        .fw_rd_mem_i   (fw_rd_mem),
        .fw_data_mem_i (fw_data_mem),
        .fw_valid_wb_i (fw_valid_wb),
        .fw_rd_wb_i    (fw_rd_wb),
        .fw_data_wb_i  (fw_data_wb),

        .pc_o         (pc_ex),
        .seq_pc_o     (seq_pc_ex),
        .instr_o      (instr_ex),
        .rs1_o        (rs1_ex),
        .mem_op_o     (mem_op_ex),
        .is_mem_op_o  (is_mem_op_ex),
        .mem_wdata_o  (mem_wdata_ex),
        .rd_o         (rd_ex),
        .reg_we_o     (reg_we_ex),
        .wb_src_o     (wb_src_ex),
        .result_o     (result_ex),
        .mult_res_wb_o(mult_result_ex)
    );

    turvo32_stage_mem mem_stage_i (
        .clk_i,
        .rst_ni,

        .ps_valid_i(ex_stage_valid),
        .ps_ready_o(mem_stage_ready),
        .ns_valid_o(mem_stage_valid),

        .rd_i        (rd_ex),
        .reg_we_i    (reg_we_ex),
        .wb_src_i    (wb_src_ex),
        .ex_result_i (result_ex),

        .jump_tgt_i   (jump_target_ex),
        .branch_tgt_i (branch_target_ex),
        .is_jump_i    (is_jump_ex),
        .is_branch_i  (is_branch_ex),
        .take_branch_i(take_branch_ex),
        .mem_op_i     (mem_op_ex),
        .is_mem_op_i  (is_mem_op_ex),
        .mem_wdata_i  (mem_wdata_ex),

        .interrupts_i,
        .pc_ex_i     (pc_ex),
        .seq_pc_ex_i (seq_pc_ex),
        .instr_ex_i  (instr_ex),
        .rs1_ex_i    (rs1_ex),
        .commit_i    (mem_stage_valid),

        .is_valid_load_o(is_valid_load_mem),

        .inval_if_o   (inval_if_mem),
        .inval_id_o   (inval_id_mem),
        .inval_ex_o   (inval_ex_mem),

        .btb_pc_o     (btb_pc_mem),
        .btb_tgt_o    (btb_tgt_mem),
        .btb_cond_o   (btb_cond_mem),
        .btb_we_o     (btb_we_mem),

        .rd_o       (rd_mem),
        .reg_we_o   (reg_we_mem),
        .wb_src_o   (wb_src_mem),
        .reg_wdata_o(reg_wdata_mem),
        .lsu_rdata_o(lsu_rdata_mem),

        .jump_tgt_o(jump_tgt_mem),
        .do_jump_o (do_jump_mem),

        .fw_valid_o(fw_valid_mem),
        .fw_rd_o   (fw_rd_mem),
        .fw_data_o (fw_data_mem),

        .dbus_o,
        .dbus_i
    );

    turvo32_stage_wb wb_stage_i (
        .clk_i,
        .rst_ni,

        .ps_valid_i(mem_stage_valid),

        .rd_i        (rd_mem),
        .reg_we_i    (reg_we_mem),
        .wb_src_i    (wb_src_mem),
        .ex_result_i (reg_wdata_mem),
        .lsu_rdata_i (lsu_rdata_mem),
        .ex_mul_res_i(mult_result_ex),

        .reg_rd_o   (rd_wb),
        .reg_we_o   (reg_we_wb),
        .reg_wdata_o(reg_wdata_wb),

        .fw_valid_o (fw_valid_wb),
        .fw_rd_o    (fw_rd_wb),
        .fw_data_o  (fw_data_wb),

        .dbus_i
    );

endmodule
