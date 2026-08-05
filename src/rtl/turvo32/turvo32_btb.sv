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

	// TODO: rework for IALIGN=16 when RVC support is added
	//       (until then, using pc[1] in the index wastes 50% of sets)

	localparam IDX_W = $clog2(SETS);
	localparam TAG_W = 30 - IDX_W; // Bit 0 is never stored
	localparam LINE_W = TAG_W + 30 + 2; // 31: dest, 2: flags (conditional, valid)

	logic [WAYID_W-1:0] hit_way_id, lru_way_id;
	logic               is_hit;

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
	logic [       1:0] flag_rdata  [WAYS-1:0];
	logic              valid_rdata [WAYS-1:0];

	generate
		for (genvar i = 0; i < WAYS; i++) begin : gen_ways
			(* ram_style = "block" *)
			logic [LINE_W-1:0] lines [SETS-1:0];

			initial lines = '{default: '0};

			assign valid_rdata[i] = flag_rdata[i][0];

			always_ff @(posedge clk_i) begin
				if (we_i && w_way_i == i) begin
					lines[w_pc_idx] <= {w_pc_i[31-:TAG_W], w_tgt_i[31:2], w_is_cond_i, 1'b1};
				end
				{tag_rdata[i], dest_rdata[i], flag_rdata[i]} <= lines[pc_d_idx];
			end
		end : gen_ways
	endgenerate

	always_comb begin
		hit_way_id = '0;
		is_hit = '0;
		pc_jump_o = '0;

		for (int i = 0; i < WAYS; i++) begin
			if (tag_rdata[i] == pc_tag_q && valid_rdata[i]) begin
				hit_way_id = i;
				pc_jump_o = {dest_rdata[i], 2'b0};
				is_hit = '1;
			end
		end
	end

	assign do_jump_o = is_hit;

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

endmodule
