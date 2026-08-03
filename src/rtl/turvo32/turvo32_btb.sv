// SPDX-License-Identifier: SHL-2.1
// SPDX-FileCopyrightText: David Schröder 2026

// Branch Target Buffer.

module turvo32_btb
	import turvo32_pkg::*;
#(
	parameter  int WAYS = 4,
	parameter  int SETS = 128, // Power of two >= 2
	localparam int WAYID_W = $clog2(WAYS)
) (
	input  logic clk_i,
	input  logic rst_ni,

	input  logic [       31:0] pc_d_i,
	output logic [       31:0] pc_jump_o,
	output logic               do_jump_o,
	output logic [WAYID_W-1:0] way_o,

	input  logic [       31:0] w_pc_i,
	input  logic [       31:0] w_tgt_i,
	input  logic [WAYID_W-1:0] w_way_i,
	input  logic               w_is_cond_i,
	input  logic               we_i
);

	localparam IDX_W = $clog2(SETS);
	localparam TAG_W = 31 - IDX_W; // Bit 0 is never stored
	localparam LINE_W = TAG_W + 31 + 1; // 31: dest, 1: flags (conditional)

	logic [WAYID_W-1:0] hit_way_id, lru_way_id;
	logic               is_hit;

	logic [IDX_W-1:0] pc_d_idx;
	logic [TAG_W-1:0] pc_d_tag;
	logic [TAG_W-1:0] pc_tag_q;

	assign way_o = is_hit ? hit_way_id : lru_way_id;

	assign pc_d_idx = pc_d_i[1+:IDX_W];
	assign pc_d_tag = pc_d_i[31-:TAG_W];

	always_ff @(posedge clk_i or negedge rst_ni) begin
		if (~rst_ni) begin
			pc_tag_q <= '0;
		end else begin
			pc_tag_q <= pc_d_tag;
		end
	end

	/* Way generation */

	logic [ TAG_W-1:0] tag_rdata   [WAYS-1:0];
	logic [      30:0] dest_rdata  [WAYS-1:0];
	logic [       0:0] flag_rdata  [WAYS-1:0];
	logic              valid_rdata [WAYS-1:0];

	generate
		for (genvar i = 0; i < WAYS; i++) begin : gen_ways
			logic [LINE_W-1:0] lines [SETS-1:0];
			logic              valid [SETS-1:0];

			initial lines = '{default: '0};
			initial valid = '{default: '0};

			always_ff @(posedge clk_i or negedge rst_ni) begin
				if (~rst_ni) begin
					tag_rdata[i] <= '0;
					dest_rdata[i] <= '0;
					flag_rdata[i] <= '0;
					valid_rdata[i] <= '0;
				end else begin
					{tag_rdata[i], dest_rdata[i], flag_rdata[i]} <= lines[pc_d_idx];
					valid_rdata[i] <= valid[pc_d_idx];
				end
			end

			always_ff @(posedge clk_i) begin
				if (we_i && w_way_i == i) begin
					lines[w_pc_i[1+:IDX_W]] <= {w_pc_i[31-:TAG_W], w_tgt_i[31:1], w_is_cond_i};
					valid[w_pc_i[1+:IDX_W]] <= '1;
				end
			end
		end : gen_ways
	endgenerate

	always_comb begin
		hit_way_id = '0;
		is_hit = '0;

		for (int i = 0; i < WAYS; i++) begin
			if (tag_rdata[i] == pc_tag_q && valid_rdata[i]) begin
				hit_way_id = i;
				is_hit = '1;
			end
		end
	end

	assign pc_jump_o = {dest_rdata[hit_way_id], 1'b0};
	assign do_jump_o = is_hit && !flag_rdata[hit_way_id][0]; // only predict uncond. jumps for now

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
		.use_addr_i(w_pc_i[1+:IDX_W])
	);

endmodule
