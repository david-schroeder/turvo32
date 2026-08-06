// SPDX-License-Identifier: SHL-2.1
// SPDX-FileCopyrightText: David Schröder 2026

module turvo32_stage_ex
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

    // ID stage inputs
    input  logic [31:0] pc_i,
    input  logic [31:0] pc_seq_i,
    input  logic [31:0] instr_i,
    input  logic [ 4:0] ra1_i,
    input  logic [ 4:0] ra2_i,
    input  logic [31:0] rs1_i,
    input  logic [31:0] rs2_i,
    input  logic [31:0] imm_i,
    input  alu_src1_e   alu_src1_i,
    input  alu_src2_e   alu_src2_i,
    input  alu_op_e     alu_op_i,
    input  shift_op_e   shift_op_i,
    input  branch_e     branch_i,
    input  logic        is_branch_i,
    input  logic        is_jump_i,
    input  mult_op_e    mult_op_i,
    input  div_op_e     div_op_i,
    input  logic        is_mult_i,
    input  logic        is_div_i,
    input  mem_op_e     mem_op_i,
    input  logic        is_mem_op_i,
    input  logic [ 4:0] rd_i,
    input  logic        reg_we_i,
    input  wb_src_e     wb_src_i,

    // ID stage stall control (datahazards)
    output logic        is_valid_mult_o,
    output logic        is_valid_load_o,
    output logic        is_valid_csrr_o,

    // MEM / WB stage CE inputs for mult
    input  logic        ce_mem_i,
    input  logic        ce_wb_i,

    // Jump / Branch outputs
    output logic [31:0] jump_target_o,
    output logic [31:0] branch_target_o,
    output logic        is_branch_o,
    output logic        is_jump_o,
    output logic        take_branch_o,

    // Forwarding inputs
    input  logic        fw_valid_mem_i,
    input  logic [ 4:0] fw_rd_mem_i,
    input  logic [31:0] fw_data_mem_i,
    input  logic        fw_valid_wb_i,
    input  logic [ 4:0] fw_rd_wb_i,
    input  logic [31:0] fw_data_wb_i,

    // Other passthrough signals
    input  logic [PASSTHROUGH_W-1:0] passthru_i,
    output logic [PASSTHROUGH_W-1:0] passthru_o,

    // MEM stage outputs
    output logic [31:0] pc_o,
    output logic [31:0] seq_pc_o,
    output logic [31:0] linear_pc_o,
    output logic [31:0] instr_o,
    output logic [31:0] rs1_o,
    output mem_op_e     mem_op_o,
    output logic        is_mem_op_o,
    output logic [31:0] mem_wdata_o,
    output logic [ 4:0] rd_o,
    output logic        reg_we_o,
    output wb_src_e     wb_src_o,
    output logic [31:0] result_o,
    output logic [31:0] mult_res_wb_o
);

    logic stage_ready;
    assign ps_ready_o = ns_ready_i & stage_ready;

    /////////////
    //         //
    // Signals //
    //         //
    /////////////

    logic        forward_rs1_wb;
    logic        forward_rs2_wb;
    logic [31:0] rs1_fw, rs2_fw;
    logic [31:0] operand_a, operand_b;
    logic        div_stall;

    logic        mem_op_is_load;
    logic        is_csrr;

    logic [31:0] alu_result;
    logic [31:0] shifter_result;
    logic [31:0] div_result;

    ////////////////////
    //                //
    // ID <-> EX Regs //
    //                //
    ////////////////////

    logic        valid_ex;
    logic [31:0] pc_ex;
    logic [31:0] pc_seq_ex;
    logic [31:0] instr_ex;
    logic [ 4:0] ra1_ex, ra2_ex;
    logic [31:0] rs1_ex, rs2_ex;
    logic [31:0] imm_ex;
    alu_src1_e   alu_src1_ex;
    alu_src2_e   alu_src2_ex;
    alu_op_e     alu_op_ex;
    shift_op_e   shift_op_ex;
    branch_e     branch_type_ex;
    logic        is_branch_ex;
    logic        is_jump_ex;
    mult_op_e    mult_op_ex;
    div_op_e     div_op_ex;
    logic        is_mult_ex;
    logic        is_div_ex;
    mem_op_e     mem_op_ex;
    logic        is_mem_op_ex;
    logic [ 4:0] rd_ex;
    logic        reg_we_ex;
    wb_src_e     wb_src_ex;

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (~rst_ni) begin
            valid_ex       <= '0;
            pc_ex          <= '0;
            pc_seq_ex      <= '0;
            instr_ex       <= '0;
            ra1_ex         <= '0;
            ra2_ex         <= '0;
            rs1_ex         <= '0;
            rs2_ex         <= '0;
            imm_ex         <= '0;
            alu_src1_ex    <= RS1;
            alu_src2_ex    <= RS2;
            alu_op_ex      <= ADD;
            shift_op_ex    <= SLL;
            branch_type_ex <= BEQ;
            is_branch_ex   <= '0;
            is_jump_ex     <= '0;
            mult_op_ex     <= MUL;
            is_mult_ex     <= '0;
            div_op_ex      <= DIV;
            is_div_ex      <= '0;
            mem_op_ex      <= LB;
            is_mem_op_ex   <= '0;
            rd_ex          <= '0;
            reg_we_ex      <= '0;
            wb_src_ex      <= ALU;
            passthru_o     <= '0;
        end else begin
            if (ps_ready_o) begin
                valid_ex       <= ps_valid_i;
                pc_ex          <= pc_i;
                pc_seq_ex      <= pc_seq_i;
                instr_ex       <= instr_i;
                ra1_ex         <= ra1_i;
                ra2_ex         <= ra2_i;
                rs1_ex         <= rs1_i;
                rs2_ex         <= rs2_i;
                imm_ex         <= imm_i;
                alu_src1_ex    <= alu_src1_i;
                alu_src2_ex    <= alu_src2_i;
                alu_op_ex      <= alu_op_i;
                shift_op_ex    <= shift_op_i;
                branch_type_ex <= branch_i;
                is_branch_ex   <= is_branch_i;
                is_jump_ex     <= is_jump_i;
                mult_op_ex     <= mult_op_i;
                is_mult_ex     <= is_mult_i;
                div_op_ex      <= div_op_i;
                is_div_ex      <= is_div_i;
                mem_op_ex      <= mem_op_i;
                is_mem_op_ex   <= is_mem_op_i;
                rd_ex          <= rd_i;
                reg_we_ex      <= reg_we_i;
                wb_src_ex      <= wb_src_i;
                passthru_o     <= passthru_i;
            end else begin
                // EX stage is stalled; handle edge case:
                // WB stage is not stalled and data will no longer
                // be available for forwarding next cycle, so
                // update rs*_ex instead if rd matches
                if (forward_rs1_wb) rs1_ex <= fw_data_wb_i;
                if (forward_rs2_wb) rs2_ex <= fw_data_wb_i;
            end
        end
    end

    assign ns_valid_o = valid_ex && ps_ready_o && !invalidate_i;

    /////////////////
    //             //
    // Stage Logic //
    //             //
    /////////////////

    always_comb begin
        // RS1 forwarder
        priority case (1'b1)
            fw_valid_mem_i && fw_rd_mem_i == ra1_ex: rs1_fw = fw_data_mem_i;
            forward_rs1_wb: rs1_fw = fw_data_wb_i;
            default: rs1_fw = rs1_ex;
        endcase

        // RS2 forwarder
        priority case (1'b1)
            fw_valid_mem_i && fw_rd_mem_i == ra2_ex: rs2_fw = fw_data_mem_i;
            forward_rs2_wb: rs2_fw = fw_data_wb_i;
            default: rs2_fw = rs2_ex;
        endcase

        // Operand A mux
        unique case (alu_src1_ex)
            RS1: operand_a = rs1_fw;
            PC : operand_a = pc_ex;
            default: operand_a = '0;
        endcase

        // Operand B mux
        unique case (alu_src2_ex)
            RS2: operand_b = rs2_fw;
            default: operand_b = imm_ex;
        endcase

        // Result mux
        unique case (wb_src_ex)
            SHIFTER: result_o = shifter_result;
            DIVIDER: result_o = div_result;
            SEQ_PC : result_o = linear_pc_o; // TODO: adjust for RVC
            default: result_o = alu_result;
        endcase
    end

    assign linear_pc_o = pc_ex + 4;

    assign forward_rs1_wb = fw_valid_wb_i && fw_rd_wb_i == ra1_ex;
    assign forward_rs2_wb = fw_valid_wb_i && fw_rd_wb_i == ra2_ex;

    assign branch_target_o = pc_ex + imm_ex;
    assign jump_target_o   = {alu_result[31:1], 1'b0};

    assign stage_ready = ~div_stall;

    assign is_branch_o = is_branch_ex;
    assign is_jump_o   = is_jump_ex;

    assign mem_op_o    = mem_op_ex;
    assign is_mem_op_o = is_mem_op_ex;
    assign mem_wdata_o = rs2_fw;

    assign rd_o     = rd_ex;
    assign reg_we_o = reg_we_ex;
    assign wb_src_o = wb_src_ex;

    assign mem_op_is_load  = mem_op_ex inside {LB, LBU, LH, LHU, LW};
    assign is_csrr = instr_ex[6:0] == 7'h73 && instr_ex[14:12] != '0;
    assign is_valid_mult_o = valid_ex && is_mult_ex;
    assign is_valid_load_o = valid_ex && is_mem_op_ex && mem_op_is_load;
    assign is_valid_csrr_o = valid_ex && is_csrr && rd_ex != '0;

    assign rs1_o    = rs1_fw;
    assign pc_o     = pc_ex;
    assign seq_pc_o = pc_seq_ex;
    assign instr_o  = instr_ex;

    ///////////////////
    //               //
    // Instantiation //
    //               //
    ///////////////////

    turvo32_alu alu_i (
        .a_i          (operand_a),
        .b_i          (operand_b),
        .op_i         (alu_op_ex),
        .res_o        (alu_result),
        .branch_i     (branch_type_ex),
        .take_branch_o
    );

    turvo32_shifter shifter_i (
        .data_i (operand_a),
        .shamt_i(operand_b),
        .op_i   (shift_op_ex),
        .data_o (shifter_result)
    );

    turvo32_mult mult_i (
        .clk_i,
        .rst_ni,

        .rs1_i    (rs1_fw),
        .rs2_i    (rs2_fw),
        .ce_mem_i,
        .ce_wb_i,
        .op_i     (mult_op_ex),
        .result_o (mult_res_wb_o)
    );

    turvo32_divider div_i (
        .clk_i,
        .rst_ni,

        .rs1_i      (rs1_fw),
        .rs2_i      (rs2_fw),
        .result_o   (div_result),
        .op_i       (div_op_ex),
        .is_div_i   (is_div_ex && valid_ex && !invalidate_i),
        .div_stall_o(div_stall)
    );

endmodule
