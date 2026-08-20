// SPDX-License-Identifier: SHL-2.1
// SPDX-FileCopyrightText: David Schröder 2026

// Branch Target Buffer with Branch Predictor.

module turvo32_btb
	import turvo32_pkg::*;
#(
	parameter  int WAYS = 4,
	parameter  int SETS = 128, // Power of two >= 2
	localparam int WAYID_W = $clog2(WAYS),
	parameter  int BP_N = 13 // Predictor size 2^(N-2) bytes
) (
	input  logic clk_i,
	input  logic rst_ni,

	input  logic [       31:0] pc_d_i,
	output logic [       31:0] pc_jump_o,
	output logic               do_jump_o,
	output logic               is_hit_o,
	output logic [WAYID_W-1:0] way_o,

	input  logic [       31:0] w_pc_i,
	input  logic [       31:0] w_tgt_i,
	input  logic [WAYID_W-1:0] w_way_i,
	input  logic               w_is_cond_i,
	input  logic               we_i,

	output logic [   BP_N-1:0] bp_waddr_o,
	output logic [        1:0] bp_wstate_o,
	input  logic               bp_ghr_we_i,
	input  logic [   BP_N-1:0] bp_ghr_wd_i,
	input  logic               bp_we_i,
	input  logic [   BP_N-1:0] bp_waddr_i,
	input  logic [        1:0] bp_wstate_i,
	input  logic               bp_wtaken_i
);

	// TODO: rework for IALIGN=16 when RVC support is added
	//       (until then, using pc[1] in the index wastes 50% of sets)

	localparam IDX_W = $clog2(SETS);
	localparam TAG_W = 30 - IDX_W; // Bit 0 is never stored

	logic [WAYID_W-1:0] hit_way_id, lru_way_id;
	logic               is_hit;
	logic               is_branch;
	logic               predict_taken;

	logic [IDX_W-1:0] pc_d_idx;
	logic [TAG_W-1:0] pc_d_tag;
	logic [TAG_W-1:0] pc_tag_q;
	logic [IDX_W-1:0] w_pc_idx;

	assign way_o = is_hit ? hit_way_id : lru_way_id;

	assign pc_d_idx = pc_d_i[2+:IDX_W];
	assign pc_d_tag = pc_d_i[31-:TAG_W];
	assign w_pc_idx = w_pc_i[2+:IDX_W];

	always_ff @(posedge clk_i or negedge rst_ni) begin
		if (~rst_ni) begin
			pc_tag_q <= '0;
		end else begin
			pc_tag_q <= pc_d_tag;
		end
	end

	/* Way generation */

	logic [ TAG_W-1:0] tag_rdata   [WAYS-1:0];
	logic [      29:0] dest_rdata  [WAYS-1:0];
	logic              valid_rdata [WAYS-1:0];
	logic              cond_rdata  [WAYS-1:0];

	generate
		for (genvar i = 0; i < WAYS; i++) begin : gen_ways
			prim_sram_sdp #(
				.WIDTH(64),
				.DEPTH(SETS)
			) way_i (
				.clk_i,
				.waddr_i(w_pc_idx),
				.wen_i  (we_i && w_way_i == i),
				.wdata_i({
					w_pc_i[31-:TAG_W],
					w_tgt_i[31:2],
					w_is_cond_i,
					1'b1
				}),
				.raddr_i(pc_d_idx),
				.ren_i  ('1),
				.rdata_o({
					tag_rdata[i],
					dest_rdata[i],
					cond_rdata[i],
					valid_rdata[i]
				})
			);
		end : gen_ways
	endgenerate

	always_comb begin
		hit_way_id = '0;
		is_hit = '0;
		is_branch = '0;
		pc_jump_o = '0;
		do_jump_o = '0;

		for (int i = 0; i < WAYS; i++) begin
			if (tag_rdata[i] == pc_tag_q && valid_rdata[i]) begin
				hit_way_id = i;
				pc_jump_o = {dest_rdata[i], 2'b0};
				is_hit = '1;
				is_branch = cond_rdata[i];
				do_jump_o = !cond_rdata[i] || predict_taken;
			end
		end
	end

	assign is_hit_o  = is_hit;

	turvo32_lru #(
		.WAYS   (WAYS),
		.ENTRIES(SETS)
	) lru_i (
		.clk_i,
		.rst_ni,
		.r_addr_i  (pc_d_idx),
		.lru_way_o (lru_way_id),
		.use_i     (we_i),
		.use_way_i (w_way_i),
		.use_addr_i(w_pc_idx)
	);

	turvo32_gshare #(
		.N(BP_N)
	) branch_predictor_i (
		.clk_i,
		.rst_ni,

		.pc_d_i,
		.is_branch_i(is_branch),
		.btb_hit_i  (is_hit),

		.pred_o     (predict_taken),
		.lp_addr_o  (bp_waddr_o),
		.lp_state_o (bp_wstate_o),

		.ghr_we_i   (bp_ghr_we_i),
		.ghr_wd_i   (bp_ghr_wd_i),
		.lp_we_i    (bp_we_i),
		.lp_waddr_i (bp_waddr_i),
		.lp_wstate_i(bp_wstate_i),
		.lp_wtaken_i(bp_wtaken_i)
	);

endmodule
