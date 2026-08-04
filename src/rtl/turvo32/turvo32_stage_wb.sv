// SPDX-License-Identifier: SHL-2.1
// SPDX-FileCopyrightText: David Schröder 2026

module turvo32_stage_wb
    import turvo32_pkg::*;
    import tilelink_pkg::*;
(
    input  logic clk_i,
    input  logic rst_ni,

    // Stage control
    input  logic ps_valid_i,

    // MEM stage inputs
    input  logic [ 4:0] rd_i,
    input  logic        reg_we_i,
    input  wb_src_e     wb_src_i,
    input  logic [31:0] ex_result_i,
    input  logic [31:0] lsu_rdata_i,
    input  logic [31:0] ex_mul_res_i,

    // Regfile writeback outputs
    output logic [ 4:0] reg_rd_o,
    output logic        reg_we_o,
    output logic [31:0] reg_wdata_o,

    // Forwarding outputs
    output logic        fw_valid_o,
    output logic [ 4:0] fw_rd_o,
    output logic [31:0] fw_data_o,

    input  tl_d2h_t dbus_i
);

    /////////////
    //         //
    // Signals //
    //         //
    /////////////

    logic [31:0] wb_data;

    /////////////////////
    //                 //
    // MEM <-> WB Regs //
    //                 //
    /////////////////////

    logic        valid_wb;
    logic [ 4:0] rd_wb;
    logic        reg_we_wb;
    wb_src_e     wb_src_wb;
    logic [31:0] ex_result_wb;

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (~rst_ni) begin
            valid_wb     <= '0;
            rd_wb        <= '0;
            reg_we_wb    <= '0;
            wb_src_wb    <= ALU;
            ex_result_wb <= '0;
        end else begin
            valid_wb     <= ps_valid_i;
            rd_wb        <= rd_i;
            reg_we_wb    <= reg_we_i;
            wb_src_wb    <= wb_src_i;
            ex_result_wb <= ex_result_i;
        end
    end

    /////////////////
    //             //
    // Stage Logic //
    //             //
    /////////////////

    always_comb begin
        unique case (wb_src_wb)
            ALU,
            SHIFTER,
            DIVIDER,
            LSU, // don't treat LSU separately here so it isn't forwarded
            SEQ_PC,
            CSR    : wb_data = ex_result_wb;
            MULT   : wb_data = ex_mul_res_i;
            default: wb_data = '1; // 0xFFFFFFFF for debugging
        endcase
    end

    assign reg_rd_o    = rd_wb;
    // lsu_rdata_i is not buffered (i.e., it is but in the LSU)
    assign reg_wdata_o = wb_src_wb == LSU ? lsu_rdata_i : wb_data;
    assign reg_we_o    = valid_wb && reg_we_wb;
    assign fw_rd_o     = rd_wb;
    assign fw_data_o   = wb_data;
    assign fw_valid_o  = valid_wb && reg_we_wb && rd_wb != '0;

endmodule
