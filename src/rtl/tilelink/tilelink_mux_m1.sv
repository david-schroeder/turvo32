// SPDX-License-Identifier: SHL-2.1
// SPDX-FileCopyrightText: David Schröder 2026

module tilelink_mux_m1
	import tilelink_pkg::*;
#(
	// clog2(N) + clog2(MAX_OUTSTANDING) must be <= # TL source bits
	parameter int N = 4,
	parameter int MAX_OUTSTANDING = 4
) (
	input  logic clk_i,
	input  logic rst_ni,

	input  tl_h2d_t host_i [N-1:0],
	output tl_d2h_t host_o [N-1:0],
	output tl_h2d_t device_o,
	input  tl_d2h_t device_i
);

	localparam int LOGN = $clog2(N);
	localparam int OUT_SRCW = $clog2(MAX_OUTSTANDING);
	localparam int IN_SRCW = $bits(host_i[0].a_source);

	/* Source table / response routing */

	logic [ IN_SRCW-1:0] src_table [MAX_OUTSTANDING-1:0];
	logic [OUT_SRCW-1:0] wptr;
	logic [  OUT_SRCW:0] outstanding; // needs one more bit
	logic                full;

	logic a_exchange, d_exchange;
	assign a_exchange = device_o.a_valid && device_i.a_ready;
	assign d_exchange = device_i.d_valid && device_o.d_ready;

	assign full = outstanding == MAX_OUTSTANDING;

	always_ff @(posedge clk_i or negedge rst_ni) begin
		if (~rst_ni) begin
			wptr <= '0;
			outstanding <= '0;
		end else begin
			if (a_exchange) wptr <= wptr + 1;
			case ({a_exchange, d_exchange})
				{1'b0, 1'b1}: outstanding <= outstanding - 1;
				{1'b1, 1'b0}: outstanding <= outstanding + 1;
				default: ;
			endcase
		end
	end

	/* Arbitration (round-robin) */

	logic [LOGN-1:0] prio_d    [N-1:0];
	logic [LOGN-1:0] prio_q    [N-1:0];
	logic [   N-1:0] req_match;
	// gte_match[i] = 1 -> request of greater or equal prio exists
	logic [   N-1:0] gte_match;
	logic [   N-1:0] winner;
	logic [LOGN-1:0] winner_id; // id of set bit in winner bitmask
	logic [LOGN-1:0] win_host_id; // actual winning host

	always_ff @(posedge clk_i or negedge rst_ni) begin
		if (~rst_ni) begin
			for (int i = 0; i < N; i++) prio_q[i] <= i;
		end else begin
			for (int i = 0; i < N; i++) prio_q[i] <= prio_d[i];
		end
	end

	generate
		for (genvar i = 0; i < N; i++) begin : gen_matches
			assign req_match[i] = host_i[prio_q[i]].a_valid && !full;
			assign gte_match[i] = |req_match[i:0];
		end : gen_matches
	endgenerate

	always_comb begin
		winner[0] = gte_match[0];
		winner_id = '0;
		for (int i = 1; i < N; i++) begin
			winner[i] = gte_match[i] & ~gte_match[i - 1];
			if (winner[i]) winner_id = i;
		end

		prio_d = prio_q;
		if (a_exchange) begin
			for (int i = 0; i < N; i++) begin
				prio_d[i] = prio_q[(LOGN)'(winner_id + i + 1)];
			end
		end
	end

	assign win_host_id = prio_q[winner_id];

	/* Source table updates */

	always_ff @(posedge clk_i) begin
		if (a_exchange) begin
			src_table[wptr] <= host_i[win_host_id].a_source;
		end
	end

	/* Output generation */

	always_comb begin
		for (int i = 0; i < N; i++) begin
			host_o[i] = '{
				d_valid: device_i.d_valid && device_i.d_source[LOGN-1:0] == i,
				d_opcode: device_i.d_opcode,
				d_source: src_table[device_i.d_source[LOGN+:OUT_SRCW]],
				d_size: device_i.d_size,
				d_data: device_i.d_data,
				d_denied: device_i.d_denied,
				a_ready: win_host_id == i && device_i.a_ready
			};
		end

		device_o = '{a_opcode: Get, default: '0};

		for (int i = 0; i < N; i++) begin
			if (winner[i]) device_o = host_i[prio_q[i]];
		end

		device_o.d_ready = host_i[device_i.d_source[LOGN-1:0]].d_ready;
		device_o.a_source = {wptr, win_host_id};
	end

endmodule
