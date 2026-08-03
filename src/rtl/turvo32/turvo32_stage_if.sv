// SPDX-License-Identifier: SHL-2.1
// SPDX-FileCopyrightText: David Schröder 2026

module turvo32_stage_if
    import turvo32_pkg::*;
    import tilelink_pkg::*;
#(
    parameter logic [31:0] BOOT_ADDR      = 32'h00000080,
    parameter logic [31:0] DEBUG_ADDR     = 32'h10000000,
    parameter logic [31:0] DEBUG_EXC_ADDR = 32'h10001000
) (
    input  logic clk_i,
    input  logic rst_ni,

    // Stage control
    output logic ns_valid_o,
    input  logic ns_ready_i,
    input  logic invalidate_i,

    input  logic [31:0] jump_tgt_i,
    input  logic        do_jump_i,

    output logic [31:0] pc_o,
    output logic [31:0] pc_seq_o,
    output logic [31:0] instr_o,

    input  logic [31:0] btb_pc_i,
    input  logic [31:0] btb_tgt_i,
    input  logic        btb_cond_i,
    input  logic        btb_we_i,

    output tl_h2d_t ibus_o,
    input  tl_d2h_t ibus_i
);

    /////////////
    //         //
    // Signals //
    //         //
    /////////////

    logic        valid_if;

    logic [31:0] pc_d, pc_if;
    logic [31:0] pc_seq;
    logic        is_first_cycle;

    // FTQ
    logic        ftq_ready;
    logic        ftq_bus_valid;
    logic        ftq_bus_ready;
    logic [ 1:0] ftq_src_h2d;
    logic [ 1:0] ftq_src_d2h;
    logic [31:0] ftq_bus_data;

    // BTB
    logic [31:0] btb_pred_addr;
    logic        btb_says_jump;

    /////////////
    //         //
    // IF Regs //
    //         //
    /////////////

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (~rst_ni) begin
            pc_if          <= BOOT_ADDR;
            is_first_cycle <= '1;
        end else begin
            if (ftq_ready && (!ibus_o.a_valid || ibus_i.a_ready)) begin
                pc_if          <= pc_d;
                is_first_cycle <= '0;
            end
        end
    end

    /////////////////
    //             //
    // Stage Logic //
    //             //
    /////////////////

    assign valid_if = ~is_first_cycle & ~invalidate_i;

    assign pc_seq = pc_if + 4;

    always_comb begin
        unique case (1'b1)
            is_first_cycle : pc_d = BOOT_ADDR; // First cycle after boot
            do_jump_i      : pc_d = jump_tgt_i;
            default        : pc_d = btb_says_jump ? btb_pred_addr : pc_seq;
        endcase
    end

    assign ftq_bus_valid = ibus_i.d_valid;
    assign ftq_src_d2h   = ibus_i.d_source;
    assign ftq_bus_data  = ibus_i.d_data;

    assign ibus_o = '{
        a_valid: valid_if && ftq_ready,
        a_opcode: Get,
        a_address: pc_if,
        a_source: ftq_src_h2d,
        a_size: 2'h2,
        a_mask: 4'hF,
        d_ready: ftq_bus_ready,
        default : '0
    };

    ///////////////////
    //               //
    // Instantiation //
    //               //
    ///////////////////

    /* Fetch Target Queue */

    turvo32_ftq #(
        .ANC_W(32)
    ) ftq_i (
        .clk_i,
        .rst_ni,

        .invalidate_i,

        .req_address_i(pc_if),
        .req_anc_i    (pc_d),
        .req_valid_i  (valid_if && ftq_ready && ibus_i.a_ready),
        .req_ready_o  (ftq_ready),

        .rsp_address_o(pc_o),
        .rsp_anc_o    (pc_seq_o),
        .rsp_data_o   (instr_o),
        .rsp_valid_o  (ns_valid_o),
        .rsp_ready_i  (ns_ready_i),

        .bus_valid_i  (ftq_bus_valid),
        .bus_ready_o  (ftq_bus_ready),
        .bus_src_i    (ftq_src_d2h),
        .bus_src_o    (ftq_src_h2d),
        .bus_data_i   (ftq_bus_data)
    );

    /* Branch Target Buffer */

    turvo32_btb btb_i (
        .clk_i,
        .rst_ni,

        .pc_d_i     (pc_d),
        .pc_jump_o  (btb_pred_addr),
        .do_jump_o  (btb_says_jump),
        .way_o      (),

        .w_pc_i     (btb_pc_i),
        .w_way_i    ('0),
        .w_tgt_i    (btb_tgt_i),
        .w_is_cond_i(btb_cond_i),
        .we_i       (btb_we_i)
    );

endmodule
