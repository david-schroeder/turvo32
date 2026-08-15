// SPDX-License-Identifier: SHL-2.1
// SPDX-FileCopyrightText: David Schröder 2026

// Fetch Target Queue for TURVo32.

module turvo32_ftq
	import turvo32_pkg::*;
	import tilelink_pkg::*;
#(
	parameter  int ENTRIES = 4,
	parameter  int ANC_W = 1,
	localparam int ENTRY_AW = $clog2(ENTRIES)
) (
	input  logic clk_i,
	input  logic rst_ni,

	input  logic invalidate_i,

	input  logic [        31:0] req_address_i,
	input  logic [   ANC_W-1:0] req_anc_i, // ancillary request data
	input  logic                req_valid_i, // request transaction this cycle
	output logic                req_ready_o,

	output logic [        31:0] rsp_address_o,
	output logic [        31:0] rsp_data_o,
	output logic                rsp_error_o,
	output logic [   ANC_W-1:0] rsp_anc_o,
	output logic                rsp_valid_o,
	input  logic                rsp_ready_i,

	input  logic                bus_valid_i,
	output logic                bus_ready_o,
	input  logic [ENTRY_AW-1:0] bus_src_i,
	output logic [ENTRY_AW-1:0] bus_src_o,
	input  logic [        31:0] bus_data_i,
	input  logic                bus_error_i
);

	logic [     31:0] entry_addrs     [ENTRIES-1:0];
	logic [ANC_W-1:0] entry_ancillary [ENTRIES-1:0];
	logic [     31:0] entry_data      [ENTRIES-1:0];
	logic             entry_error     [ENTRIES-1:0];

	logic [ENTRIES-1:0] entry_pending_d, entry_pending_q;
	logic [ENTRIES-1:0] entry_valid_d,   entry_valid_q;
	logic [ENTRIES-1:0] accept_data_writes;

	logic [ENTRY_AW-1:0] rptr;
	logic [ENTRY_AW-1:0] wptr;

	logic rsp_handshake;

	logic bus_handshake;
	logic bus_matches_rptr;
	logic bus_rsp_direct;

	logic is_same_cyc_rsp;

	assign rsp_handshake = rsp_valid_o && rsp_ready_i;

	assign bus_handshake    = bus_valid_i && bus_ready_o;
	assign bus_matches_rptr = bus_src_i == rptr;
	assign bus_rsp_direct   = bus_handshake && bus_matches_rptr;
	assign bus_ready_o      = '1;
	assign bus_src_o        = wptr;

	assign is_same_cyc_rsp = bus_handshake && req_valid_i && bus_src_o == bus_src_i;

	// We're intentionally never ready when the buffer is full:
	// It would theoretically be possible to allow a request if a response arrives in the same
	// cycle, but TileLink explicitly forbids gating request validation on a same-cycle response.
	assign req_ready_o = rptr != wptr                                     // Buffer not at HWM / full
	                  || !(entry_valid_q[rptr] || entry_pending_q[rptr]); // HWM but not full

	assign rsp_valid_o   = (bus_rsp_direct ? entry_pending_q[rptr] : entry_valid_q[rptr]);
	assign rsp_data_o    = bus_rsp_direct ? bus_data_i : entry_data[rptr];
	assign rsp_error_o   = bus_rsp_direct ? bus_error_i : entry_error[rptr];
	assign rsp_address_o = is_same_cyc_rsp ? req_address_i : entry_addrs[rptr];
	assign rsp_anc_o     = is_same_cyc_rsp ? req_anc_i : entry_ancillary[rptr];

	/* State update logic */

	always_comb begin
		entry_pending_d    = entry_pending_q;
		entry_valid_d      = entry_valid_q;
		accept_data_writes = '0;

		if (req_valid_i) entry_pending_d[wptr] = '1;
		if (bus_handshake && entry_pending_d[bus_src_i]) begin
			entry_pending_d[bus_src_i] = '0;
			entry_valid_d[bus_src_i] = '1;
			accept_data_writes[bus_src_i] = '1;
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
			if (req_valid_i) wptr <= wptr + 1;
			if (invalidate_i) begin
				entry_pending_q <= '0;
				entry_valid_q <= '0;
				rptr <= rptr;
				wptr <= rptr;
			end
		end
	end

	always_ff @(posedge clk_i) begin
		if (req_valid_i) begin
			entry_addrs[wptr] <= req_address_i;
			entry_ancillary[wptr] <= req_anc_i;
		end
		if (accept_data_writes[bus_src_i]) begin
			entry_data[bus_src_i] <= bus_data_i;
			entry_error[bus_src_i] <= bus_error_i;
		end
	end

	initial begin
		entry_ancillary <= '{default: '0};
		entry_addrs     <= '{default: '0};
		entry_data      <= '{default: '0};
		entry_error     <= '{default: '0};
	end

endmodule
