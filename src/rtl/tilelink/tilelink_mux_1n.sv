// SPDX-License-Identifier: SHL-2.1
// SPDX-FileCopyrightText: David Schröder 2026

module tilelink_mux_1n
	import tilelink_pkg::*;
#(
	parameter int N = 4,
	// bits DEVSEL_BIT_LO +: $clog2(N) are used to derive target device
	parameter int DEVSEL_BIT_LO = 20
) (
	input  tl_h2d_t host_i,
	output tl_d2h_t host_o,
	output tl_h2d_t device_o [N-1:0],
	input  tl_d2h_t device_i [N-1:0]
);

	localparam int DEVSEL_BITS = $clog2(N);

	logic [DEVSEL_BITS-1:0] selected_device;
	assign selected_device = host_i.a_address[DEVSEL_BIT_LO +: DEVSEL_BITS];

	always_comb begin
		for (int i = 0; i < N; i++) begin
			device_o[i] = host_i;
			device_o[i].d_ready = '0;
			device_o[i].a_valid = '0;
		end
		host_o = device_i[0];

		device_o[selected_device] = host_i;

		for (int i = 0; i < N; i++) begin
			if (device_i[i].d_valid) begin
				host_o = device_i[i];
				device_o[i].d_ready = host_i.d_ready;
			end
		end

		host_o.a_ready = device_i[selected_device].a_ready;

		if (selected_device > N && host_i.a_valid) begin
			host_o = '{
				d_valid: '1,
				d_opcode: host_i.a_opcode == Get ? AccessAckData : AccessAck,
				d_size: host_i.a_size,
				d_source: host_i.a_source,
				d_data: '0,
				d_denied: '1,
				a_ready: host_i.d_ready
			};
		end
	end

endmodule
