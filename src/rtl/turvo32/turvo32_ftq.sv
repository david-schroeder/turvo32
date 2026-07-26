// SPDX-License-Identifier: SHL-2.1
// SPDX-FileCopyrightText: David Schröder 2026

// Fetch Target Queue for TURVo32.

module turvo32_ftq
	import turvo32_pkg::*;
	import tilelink_pkg::*;
#(
	parameter  int ENTRIES = 4,
	localparam int ENTRY_AW = $clog2(ENTRIES)
) (
	input  logic clk_i,
	input  logic rst_ni,

	input  logic [        31:0] req_address_i,
	input  logic                req_valid_i,
	output logic                req_ready_o,

	output logic [        31:0] rsp_address_o,
	output logic [        31:0] rsp_data_o,
	output logic                rsp_valid_o,
	input  logic                rsp_ready_i,

	input  logic                bus_valid_i,
	output logic                bus_ready_o,
	input  logic [ENTRY_AW-1:0] bus_src_i,
	output logic [ENTRY_AW-1:0] bus_src_o,
	input  logic [        31:0] bus_data_i
);

	logic [31:0] entry_addrs [ENTRIES-1:0];
	logic [31:0] entry_data  [ENTRIES-1:0];

	logic [ENTRIES-1:0] entry_pending_d, entry_pending_q;
	logic [ENTRIES-1:0] entry_valid_d,   entry_valid_q;

	logic [ENTRY_AW-1:0] rptr;
	logic [ENTRY_AW-1:0] wptr;

	logic req_handshake;
	logic rsp_handshake;

	logic bus_handshake;
	logic bus_matches_rptr;
	logic bus_rsp_direct;

	logic is_same_cyc_rsp;

	assign req_handshake = req_valid_i && req_ready_o;
	assign rsp_handshake = rsp_valid_o && rsp_ready_i;

	assign bus_handshake    = bus_valid_i && bus_ready_o;
	assign bus_matches_rptr = bus_src_i == rptr;
	assign bus_rsp_direct   = bus_handshake && bus_matches_rptr;
	// TODO: check if waiting for subsequent stages might cause a deadlock
	assign bus_ready_o      = bus_matches_rptr ? rsp_ready_i : '1;
	assign bus_src_o        = wptr;

	// We're intentionally never ready when the buffer is full:
	// It would theoretically be possible to allow a request if a response arrives in the same
	// cycle, but TileLink explicitly forbids gating request validation on a same-cycle response.
	assign req_ready_o = rptr != wptr                                     // Buffer not at HWM / full
	                  || !(entry_valid_q[rptr] || entry_pending_q[rptr]); // HWM but not full

	assign rsp_valid_o   = bus_rsp_direct ? '1 : entry_valid_q[rptr];
	assign rsp_data_o    = bus_rsp_direct ? bus_data_i : entry_data[rptr];
	assign rsp_address_o = entry_valid_q[rptr] ? entry_addrs[rptr] : req_address_i;

	/* State update logic */

	always_comb begin
		entry_pending_d = entry_pending_q;
		entry_valid_d   = entry_valid_q;

		if (req_handshake) entry_pending_d[wptr] = '1;
		if (bus_handshake) begin
			entry_pending_d[bus_src_i] = '0;
			entry_valid_d[bus_src_i] = '1;
		end
		if (rsp_handshake) entry_valid_d[rptr] = '0;
	end

	always_ff @(posedge clk_i or negedge rst_ni) begin
		if (~rst_ni) begin
			rptr            <= '0;
			wptr            <= '0;
			entry_pending_q <= '0;
			entry_valid_q   <= '0;
		end else begin
			entry_pending_q <= entry_pending_d;
			entry_valid_q   <= entry_valid_d;
			if (rsp_handshake) rptr <= rptr + 1;
			if (req_handshake) wptr <= wptr + 1;
		end
	end

	always_ff @(posedge clk_i) begin
		if (req_handshake) entry_addrs[wptr] <= req_address_i;
		if (entry_valid_d[bus_src_i]) entry_data[bus_src_i] <= bus_data_i;
	end

	initial begin
		entry_addrs <= '{default: '0};
		entry_data  <= '{default: '0};
	end

endmodule
