// SPDX-License-Identifier: SHL-2.1
// SPDX-FileCopyrightText: David Schröder 2026

// NanoSoC -- minimal SoC for TURVo32.

module nanosoc_core (
    input  logic clk_i, // 100MHz clock
    input  logic rst_ni,
    input  top_pkg::board2fpga_t io_i,
    output top_pkg::fpga2board_t io_o
);

    import tilelink_pkg::*;

    `define STRINGIFY(x) `"x`"

    tl_h2d_t ibus_req, dbus_req;
    tl_d2h_t ibus_rsp, dbus_rsp;

    turvo32_pipelined uproc_i (
        .clk_i,
        .rst_ni,
        .interrupts_i('0),
        .ibus_o      (ibus_req),
        .ibus_i      (ibus_rsp),
        .dbus_o      (dbus_req),
        .dbus_i      (dbus_rsp)
    );

    nanosoc_ram #(
        .LOG_SIZE(17),
        .MEMFILE(`STRINGIFY(`INIT_MEM_FILE))
    ) iram_i (
        .clk_i,
        .rst_ni,
        .tl_i  (ibus_req),
        .tl_o  (ibus_rsp)
    );

    nanosoc_ram #(
        .LOG_SIZE(17),
        .MEMFILE(`STRINGIFY(`INIT_MEM_FILE))
    ) dram_i (
        .clk_i,
        .rst_ni,
        .tl_i  (dbus_req),
        .tl_o  (dbus_rsp)
    );

    always_comb begin
        io_o = '{default: '0};
        unique case (io_i.switch[1:0])
            2'b00: io_o.led = dbus_req.a_address[ 7: 0];
            2'b01: io_o.led = dbus_req.a_address[15: 8];
            2'b10: io_o.led = dbus_req.a_address[23:16];
            2'b11: io_o.led = dbus_req.a_address[31:24];
        endcase
    end

endmodule
