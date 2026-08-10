// SPDX-License-Identifier: SHL-2.1
// SPDX-FileCopyrightText: David Schröder 2026

module turvo32_stage_mem
    import turvo32_pkg::*;
    import tilelink_pkg::*;
#(
    parameter int BTB_WAYW = 2,
    parameter int BP_N = 13
) (
    input  logic clk_i,
    input  logic rst_ni,

    // Stage control
    input  logic ps_valid_i,
    output logic ps_ready_o,
    output logic ns_valid_o,

    // EX stage inputs
    input  logic [31:0] linear_pc_i,
    input  logic [ 4:0] rd_i,
    input  logic        reg_we_i,
    input  wb_src_e     wb_src_i,
    input  logic [31:0] ex_result_i,
    input  logic [31:0] jump_tgt_i,
    input  logic [31:0] branch_tgt_i,
    input  logic        is_branch_i,
    input  logic        is_jump_i,
    input  logic        take_branch_i,
    input  mem_op_e     mem_op_i,
    input  logic        is_mem_op_i,
    input  logic [31:0] mem_wdata_i,

    // Privileged unit interface
    input  logic [31:0] interrupts_i,
    input  logic [31:0] pc_ex_i,
    input  logic [31:0] seq_pc_ex_i,
    input  logic [31:0] instr_ex_i,
    input  logic [31:0] rs1_ex_i,
    input  logic        commit_i,

    // ID Stall control (datahazards)
    output logic        is_valid_load_o,

    // Control flow management outputs
    output logic [31:0] jump_tgt_o,
    output logic        do_jump_o,
    // Stage invalidation
    output logic        inval_if_o,
    output logic        inval_id_o,
    output logic        inval_ex_o,

    // BTB interface
    input  logic                btb_hit_i,
    input  logic [BTB_WAYW-1:0] btb_way_i,
    output logic [BTB_WAYW-1:0] btb_way_o,
    output logic [        31:0] btb_pc_o,
    output logic [        31:0] btb_tgt_o,
    output logic                btb_cond_o,
    output logic                btb_we_o,

    // Branch Predictor interface
    input  logic [BP_N-1:0] bp_waddr_i,
    input  logic [     1:0] bp_wstate_i,
    output logic            bp_ghr_we_o,
    output logic [BP_N-1:0] bp_ghr_wd_o,
    output logic            bp_we_o,
    output logic [BP_N-1:0] bp_waddr_o,
    output logic [     1:0] bp_wstate_o,
    output logic            bp_wtaken_o,

    // WB stage outputs
    output logic [ 4:0] rd_o,
    output logic        reg_we_o,
    output wb_src_e     wb_src_o,
    output logic [31:0] reg_wdata_o,
    output logic [31:0] lsu_rdata_o,
    output logic        wb_stall_o,

    // Forwarding outputs
    output logic        fw_valid_o,
    output logic [ 4:0] fw_rd_o,
    output logic [31:0] fw_data_o,

    // Data bus
    output tl_h2d_t dbus_o,
    input  tl_d2h_t dbus_i
);

    logic stage_ready;
    assign ps_ready_o = stage_ready;

    /////////////
    //         //
    // Signals //
    //         //
    /////////////

    logic        lsu_stall;
    logic        lsu_wb_stall;
    logic        lsu_pending_rsp;
    logic        lsu_misaligned;

    logic [31:0] next_arch_pc;
    logic [31:0] next_true_pc;
    logic        is_mret;
    logic        is_trap;
    logic        is_exception;
    logic [31:0] trap_pc;
    logic [31:0] mepc;
    mcause_t     mcause;
    logic [31:0] csr_rdata;

    logic        cf_pred_right;
    logic        cf_pred_wrong;
    logic        branch_pred_right;
    logic        branch_pred_wrong;

    /////////////////////
    //                 //
    // EX <-> MEM Regs //
    //                 //
    /////////////////////

    logic        valid_mem;
    logic [ 4:0] rd_mem;
    logic        reg_we_mem;
    wb_src_e     wb_src_mem;
    logic [31:0] ex_result_mem;

    mem_op_e     mem_op_mem;
    logic        is_mem_op_mem;
    logic [31:0] mem_wdata_mem;

    logic [31:0] jump_tgt_mem;
    logic [31:0] branch_tgt_mem;
    logic        is_jump_mem;
    logic        is_branch_mem;
    logic        take_branch_mem;

    logic [31:0] pc_mem;
    logic [31:0] seq_pc_mem;
    logic [31:0] linear_pc_mem;
    logic [31:0] instr_mem; // Unused but useful for debugging (committed instr)

    logic        btb_hit_mem;

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (~rst_ni) begin
            valid_mem       <= '0;
            rd_mem          <= '0;
            reg_we_mem      <= '0;
            wb_src_mem      <= ALU;
            ex_result_mem   <= '0;
            mem_op_mem      <= LB;
            is_mem_op_mem   <= '0;
            mem_wdata_mem   <= '0;
            jump_tgt_mem    <= '0;
            branch_tgt_mem  <= '0;
            is_jump_mem     <= '0;
            is_branch_mem   <= '0;
            take_branch_mem <= '0;
            pc_mem          <= '0;
            seq_pc_mem      <= '0;
            linear_pc_mem   <= '0;
            instr_mem       <= '0;
            btb_hit_mem     <= '0;
            btb_way_o       <= '0;
            bp_waddr_o      <= '0;
            bp_wstate_o     <= '0;
        end else begin
            if (ps_ready_o) begin
                valid_mem       <= ps_valid_i;
                rd_mem          <= rd_i;
                reg_we_mem      <= reg_we_i;
                wb_src_mem      <= wb_src_i;
                ex_result_mem   <= ex_result_i;
                mem_op_mem      <= mem_op_i;
                is_mem_op_mem   <= is_mem_op_i;
                mem_wdata_mem   <= mem_wdata_i;
                jump_tgt_mem    <= jump_tgt_i;
                branch_tgt_mem  <= branch_tgt_i;
                is_jump_mem     <= is_jump_i;
                is_branch_mem   <= is_branch_i;
                take_branch_mem <= take_branch_i;
                pc_mem          <= pc_ex_i;
                seq_pc_mem      <= seq_pc_ex_i;
                linear_pc_mem   <= linear_pc_i;
                instr_mem       <= instr_ex_i;
                btb_hit_mem     <= btb_hit_i;
                btb_way_o       <= btb_way_i;
                bp_waddr_o      <= bp_waddr_i;
                bp_wstate_o     <= bp_wstate_i;
            end
        end
    end

    assign ns_valid_o = valid_mem && ps_ready_o && !is_exception;

    /////////////////
    //             //
    // Stage Logic //
    //             //
    /////////////////

    assign btb_pc_o = pc_mem;
    assign btb_tgt_o = is_jump_mem ? jump_tgt_mem : branch_tgt_mem;
    assign btb_cond_o = is_branch_mem;
    assign btb_we_o = valid_mem && (is_jump_mem || is_branch_mem);

    assign stage_ready = !lsu_stall;

    assign rd_o        = rd_mem;
    assign reg_we_o    = reg_we_mem;
    assign wb_src_o    = wb_src_mem;
    assign reg_wdata_o = wb_src_mem == CSR ? csr_rdata : ex_result_mem;

    assign is_valid_load_o = valid_mem && is_mem_op_mem
                           && mem_op_mem inside {LB, LBU, LH, LHU, LW};

    assign fw_valid_o = rd_mem != '0 && reg_we_mem && valid_mem;
    assign fw_rd_o    = rd_mem;
    // Forwarded data never comes from the bus (load-use stall)
    // TODO: check if we can avoid CSRR-use stalls by setting this
    //       to reg_wdata_o instead
    assign fw_data_o  = ex_result_mem;

    assign jump_tgt_o = next_true_pc;

    assign inval_if_o = do_jump_o;
    assign inval_id_o = do_jump_o;
    assign inval_ex_o = do_jump_o;

    assign is_exception = is_trap && !mcause.interrupt;

    always_comb begin
        next_arch_pc = linear_pc_mem;
        if (valid_mem) begin
            if (is_jump_mem) next_arch_pc = jump_tgt_mem;
            if (is_branch_mem && take_branch_mem) next_arch_pc = branch_tgt_mem;
            if (is_mret) next_arch_pc = mepc;
        end

        do_jump_o         = next_arch_pc != seq_pc_mem && valid_mem || is_trap;
        cf_pred_wrong     = next_arch_pc != seq_pc_mem && valid_mem;
        cf_pred_right     = next_arch_pc != linear_pc_mem && next_arch_pc == seq_pc_mem && valid_mem;
        branch_pred_right = cf_pred_right && is_branch_mem;
        branch_pred_wrong = cf_pred_wrong && is_branch_mem && btb_hit_mem;
    end

    assign next_true_pc = is_trap ? trap_pc : next_arch_pc;

    assign bp_we_o     = valid_mem && is_branch_mem;
    assign bp_wtaken_o = take_branch_mem;

    assign wb_stall_o = lsu_wb_stall;

    /* GHR */

    logic [BP_N-1:0] ghr_q, ghr_d;

    assign ghr_d = {ghr_q[BP_N-2:0], take_branch_mem};

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (~rst_ni) begin
            ghr_q <= '0;
        end else begin
            if (is_branch_mem) begin
                ghr_q <= ghr_d;
            end
        end
    end

    assign bp_ghr_wd_o = ghr_d;
    assign bp_ghr_we_o = do_jump_o;

    ///////////////////
    //               //
    // Instantiation //
    //               //
    ///////////////////

    turvo32_lsu lsu_i (
        .clk_i,
        .rst_ni,

        .data_i      (mem_wdata_mem),
        .address_i   (ex_result_mem),
        .is_mem_op_i (is_mem_op_mem),
        .op_i        (mem_op_mem),

        .data_o      (lsu_rdata_o),
        .misaligned_o(lsu_misaligned),

        .valid_i     (valid_mem),
        .stall_o     (lsu_stall),
        .wb_stall_o  (lsu_wb_stall),

        .tl_o        (dbus_o),
        .tl_i        (dbus_i)
    );

    turvo32_privileged priv_i (
        .clk_i,
        .rst_ni,

        .interrupts_i,
        .pc_i            (pc_mem),
        .next_arch_pc_i  (next_arch_pc),
        .stall_i         (~ps_ready_o),

        .mem_misaligned_i(lsu_misaligned),
        .mem_op_i        (mem_op_mem),
        .mem_addr_i      (ex_result_mem),

        .instr_ps_valid_i(ps_valid_i),
        .instr_i         (instr_ex_i),
        .rs1_i           (rs1_ex_i),
        .csr_rdata_o     (csr_rdata),
        .mret_o          (is_mret),

        .trap_o          (is_trap),
        .mcause_o        (mcause),
        .trap_pc_o       (trap_pc),
        .mepc_o          (mepc),

        .commit_i        (commit_i)
    );

endmodule
