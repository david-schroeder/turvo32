// SPDX-License-Identifier: SHL-2.1
// SPDX-FileCopyrightText: David Schröder 2026

// GShare N:N Branch Predictor.
// Based on bimodal saturating counter FSMs.

module turvo32_gshare
	import turvo32_pkg::*;
#(
	parameter int N = 13
) (
	input  logic clk_i,
	input  logic rst_ni,

	input  logic [ 31:0] pc_d_i,
	output logic         pred_o,

	// Local predictor addr/state
	// (local pred.: entry in table)
	output logic [N-1:0] lp_addr_o,
	output logic [  1:0] lp_state_o,

	input  logic         is_branch_i,
	input  logic         btb_hit_i,

	input  logic [N-1:0] ghr_wd_i,
	input  logic         ghr_we_i,

	// LP table update port
	input  logic         lp_we_i,
	input  logic [N-1:0] lp_waddr_i,
	input  logic [  1:0] lp_wstate_i,
	input  logic         lp_wtaken_i
);

	/* Addressing */

	// N-bit Global History Register
	logic [N-1:0] ghr;
	logic [N-1:0] branch_addr;
	logic [N-1:0] lp_rdaddr;

	// TODO: adjust for IALIGN=16 when RVC support is added
	assign branch_addr = pc_d_i[2+:N];
	assign lp_rdaddr = ghr ^ branch_addr;


	/* Predictor (LP) table */

	localparam logic [1:0] NOT_TAKEN_STRONG = 2'b00;
	localparam logic [1:0] NOT_TAKEN_WEAK   = 2'b01;
	localparam logic [1:0] TAKEN_WEAK       = 2'b10;
	localparam logic [1:0] TAKEN_STRONG     = 2'b11;

	logic [1:0] pred_table [2**N-1:0] = '{default: NOT_TAKEN_WEAK};

	always_ff @(posedge clk_i or negedge rst_ni) begin
		if (~rst_ni) begin
			lp_addr_o <= '0;
		end else begin
			lp_addr_o <= lp_rdaddr;
		end
	end

	logic [1:0] lp_ns; // local pred next state

	always_comb begin
		case (lp_wstate_i)
			NOT_TAKEN_STRONG: lp_ns = lp_wtaken_i ? NOT_TAKEN_WEAK : NOT_TAKEN_STRONG;
			NOT_TAKEN_WEAK  : lp_ns = lp_wtaken_i ? TAKEN_WEAK     : NOT_TAKEN_STRONG;
			TAKEN_WEAK      : lp_ns = lp_wtaken_i ? TAKEN_STRONG   : NOT_TAKEN_WEAK;
			TAKEN_STRONG    : lp_ns = lp_wtaken_i ? TAKEN_STRONG   : TAKEN_WEAK;
			default         : lp_ns = NOT_TAKEN_WEAK;
		endcase
	end

	always_ff @(posedge clk_i) begin
		if (lp_we_i) begin
			pred_table[lp_waddr_i] <= lp_ns;
		end
		lp_state_o <= pred_table[lp_rdaddr];
	end

	assign pred_o = lp_state_o[1]; // Benefit of the chosen encoding :)


	/* GHR update logic */

	logic [N-1:0] ghr_q;
	logic [N-1:0] speculative_ghr;

	assign speculative_ghr = {ghr_q[N-2:0], pred_o};

	always_ff @(posedge clk_i or negedge rst_ni) begin
		if (~rst_ni) begin
			ghr_q <= '0;
		end else begin
			if (btb_hit_i || ghr_we_i) begin
				ghr_q <= ghr;
			end
		end
	end

	always_comb begin
		ghr = ghr_q;
		if (is_branch_i) ghr = speculative_ghr;
		if (ghr_we_i) ghr = ghr_wd_i;
	end

endmodule
