// SPDX-License-Identifier: SHL-2.1
// SPDX-FileCopyrightText: David Schröder 2026

// NanoSoC -- minimal SoC for TURVo32.

module nanosoc_core (
    input  logic clk_i, // 100MHz clock
    input  logic rst_ni,
    input  logic [1:0] switch_i,
    output logic [7:0] led_o
);

    import tilelink_pkg::*;

    `define STRINGIFY(x) `"x`"

    tl_h2d_t ibus_req, dbus_req, ram_req;
    tl_d2h_t ibus_rsp, dbus_rsp, ram_rsp;

    tl_h2d_t dbus_reqs [1:0];
    tl_d2h_t dbus_rsps [1:0];

    tl_h2d_t ram_reqs [1:0];
    tl_d2h_t ram_rsps [1:0];

    assign ram_reqs[1] = dbus_reqs[0];
    assign dbus_rsps[0] = ram_rsps[1];

    logic [31:0] interrupts;
    logic [31:0] cntr;

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (~rst_ni) begin
            interrupts <= '0;
            cntr <= 32'd999;
        end else begin
            if (cntr == 1) interrupts[11] <= '1;
            else interrupts[11] <= '0;
            if (cntr > 0) cntr <= cntr - 1;
        end
    end

    turvo32_top #(
        .BTB_SETS(64),
        .BTB_WAYS(4),
        .BP_N(8)
    ) uproc_i (
        .clk_i,
        .rst_ni,
        .interrupts_i(interrupts),
        .ibus_o      (ibus_req),
        .ibus_i      (ibus_rsp),
        .dbus_o      (dbus_req),
        .dbus_i      (dbus_rsp)
    );

    tilelink_register tl_ireg_i (
        .clk_i,
        .rst_ni,
        .host_i  (ibus_req),
        .host_o  (ibus_rsp),
        .device_o(ram_reqs[0]),
        .device_i(ram_rsps[0])
    );

    nanosoc_ram #(
        .LOG_SIZE(18),
        .MEMFILE(`STRINGIFY(`INIT_MEM_FILE))
    ) ram_i (
        .clk_i,
        .rst_ni,
        .tl_i  (ram_req),
        .tl_o  (ram_rsp)
    );

    nanosoc_ram #(
        .LOG_SIZE(10),
        .ADDR_BASE(22'h200000)
    ) outram_i (
        .clk_i,
        .rst_ni,
        .tl_i  (dbus_reqs[1]),
        .tl_o  (dbus_rsps[1])
    );

    tilelink_mux_1n #(
        .N            (2),
        .DEVSEL_BIT_LO(31)
    ) tl_mux_1n_i (
        .host_i  (dbus_req),
        .host_o  (dbus_rsp),
        .device_o(dbus_reqs),
        .device_i(dbus_rsps)
    );

    tilelink_mux_m1 #(
        .N(2)
    ) tl_mux_m1_i (
        .clk_i,
        .rst_ni,
        .host_i  (ram_reqs),
        .host_o  (ram_rsps),
        .device_o(ram_req),
        .device_i(ram_rsp)
    );

    always_comb begin
        unique case (switch_i)
            2'b00: led_o = dbus_req.a_address[ 7: 0];
            2'b01: led_o = dbus_req.a_address[15: 8];
            2'b10: led_o = dbus_req.a_address[23:16];
            2'b11: led_o = dbus_req.a_address[31:24];
        endcase
    end

endmodule
