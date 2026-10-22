// SPDX-License-Identifier: SHL-2.1
// SPDX-FileCopyrightText: David Schröder 2026

// General-purpose prefetch + demand-fetch unit.
// Built with caches in mind.

module turvo32_prefetch
	import tilelink_pkg::*;
#(
	parameter int N = 8 // Number of 32-bit words in a block
) (
	input  logic clk_i,
	input  logic rst_ni,

	input  logic [31:0] req_addr_i,
	input  logic        demand_fetch_i,
	input  logic        next_fetch_i,

	// Currently stored block
	output logic [31:0] words_o [N-1:0],

	// Whether data for req_addr_i has been prefetched;
	// 1CC delay and doesn't affect internal FSM
	output logic        hit_o,

	// Whether the full currently stored block is valid
	output logic        block_valid_o,

	// Actual bus interface
	output tl_h2d_t     tl_o,
	input  tl_d2h_t     tl_i
);

	localparam int LGN         = $clog2(N);
	localparam int BLOCK_BYTES = 4 * N;

	typedef enum logic [1:0] {
		Idle,
		Fetch,
		RspWait
	} state_e;

	logic [  N-1:0] valid_q, valid_d;
	logic [   31:0] words [N-1:0];

	logic [   31:0] req_addr_q;
	logic [   31:0] block_addr_q, block_addr_d;

	// Counters must be able to hold N, thus LGN:0
	logic [  LGN:0] req_cntr_q, req_cntr_d;
	logic [  LGN:0] rsp_cntr_q, rsp_cntr_d;
	logic [LGN-1:0] req_offs_q, req_offs_d;

	state_e state_q, state_d;

	assign block_valid_o = &valid_q;

	always_comb begin
		for (int i = 0; i < N; i++) words_o[i] = words[i];

		block_addr_d = block_addr_q;
		req_cntr_d   = req_cntr_q + (tl_o.a_valid && tl_i.a_ready);
		rsp_cntr_d   = rsp_cntr_q + (tl_i.d_valid && tl_o.d_ready);
		req_offs_d   = req_offs_q;
		state_d      = state_q;
		valid_d      = valid_q;

		case (state_d)
			Idle: begin
				if (demand_fetch_i) begin
					req_cntr_d   = '0;
					rsp_cntr_d   = '0;
					valid_d      = '0;
					state_d      = Fetch;
					block_addr_d = req_addr_q;
					req_offs_d   = req_addr_q[LGN-1:0];
				end else if (next_fetch_i) begin
					req_cntr_d   = '0;
					rsp_cntr_d   = '0;
					valid_d      = '0;
					state_d      = Fetch;
					block_addr_d = req_addr_q + BLOCK_BYTES;
					req_offs_d   = '0;
				end
			end
			Fetch: begin
				if (req_cntr_d == N) state_d = RspWait;
			end
			RspWait: begin
				if (rsp_cntr_d == N) state_d = Idle;
			end
		endcase

		if (tl_i.d_valid && tl_o.d_ready) begin
			valid_d[tl_i.d_source] = '1;
		end
	end

	always_ff @(posedge clk_i or negedge rst_ni) begin
		if (~rst_ni) begin
			req_cntr_q   <= '0;
			rsp_cntr_q   <= '0;
			req_addr_q   <= '0;
			block_addr_q <= '0;
			req_offs_q   <= '0;
			state_q      <= Idle;
			valid_q      <= '0;
			words        <= '{default: '0};
		end else begin
			req_cntr_q   <= req_cntr_d;
			rsp_cntr_q   <= rsp_cntr_d;
			req_addr_q   <= req_addr_i;
			block_addr_q <= block_addr_d;
			req_offs_q   <= req_offs_d;
			state_q      <= state_d;
			valid_q      <= valid_d;

			if (tl_i.d_valid && tl_o.d_ready) begin
				words[tl_i.d_source] <= tl_i.d_data;
			end
		end
	end

endmodule
