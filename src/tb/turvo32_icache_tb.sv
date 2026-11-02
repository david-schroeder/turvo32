// SPDX-License-Identifier: SHL-2.1
// SPDX-FileCopyrightText: David Schröder 2026

module turvo32_icache_tb;

    import turvo32_pkg::*;
    import tilelink_pkg::*;

    logic clk;
    logic rstn;

    always begin
        clk <= '1;
        #5000;
        clk <= '0;
        #5000;
    end

    // DUT Logic

    logic        dut_flush;
    logic        dut_stall;
    logic [31:0] dut_pc_d;
    logic [31:0] dut_instr;
    logic        dut_hit;
    logic        dut_cacheable;
    logic        dut_valid_if;

    tl_h2d_t     dut_tl_h2d;
    tl_d2h_t     dut_tl_d2h;

    turvo32_icache #(
        .LINE_WORDS(8),
        .SETS      (32),
        .WAYS      (2)
    ) DUT (
        .clk_i         (clk),
        .rst_ni        (rstn),
        .flush_i       (dut_flush),
        .stall_if_o    (dut_stall),
        .pc_d_i        (dut_pc_d),
        .instr_o       (dut_instr),
        .hit_o         (dut_hit),
        .cacheable_if_i(dut_cacheable),
        .valid_if_i    (dut_valid_if),
        .tl_o          (dut_tl_h2d),
        .tl_i          (dut_tl_d2h)
    );

    `define STRINGIFY(x) `"x`"

    nanosoc_ram #(
        .LOG_SIZE(18),
        .MEMFILE(`STRINGIFY(`INIT_MEM_FILE))
    ) ram_i (
        .clk_i (clk),
        .rst_ni(rstn),
        .tl_i  (dut_tl_h2d),
        .tl_o  (dut_tl_d2h)
    );

    // Testbench script

    initial begin
        rstn          <= '0;
        dut_flush     <= '0;
        dut_pc_d      <= '0;
        dut_cacheable <= '1;
        dut_valid_if  <= '0;
        @(posedge clk);
        @(posedge clk);
        rstn          <= '1;
        @(posedge clk);
        dut_pc_d      <= 32'h00000080;
        @(posedge clk);
        dut_valid_if  <= '1;
        @(posedge clk);
        for (int i = 0; i < 100; i++) begin
            dut_pc_d <= dut_stall ? dut_pc_d : dut_pc_d + 4;
            @(posedge clk);
        end

        for (int i = 0; i < 100; i++) @(posedge clk);

        $finish;
    end

endmodule
