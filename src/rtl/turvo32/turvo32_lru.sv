// SPDX-License-Identifier: SHL-2.1
// SPDX-FileCopyrightText: David Schröder 2026

// Least recently used utility.

module turvo32_lru
	import turvo32_pkg::*;
#(
	parameter  int WAYS    = 4,
	parameter  int ENTRIES = 16,
	localparam int ENTBITS = $clog2(WAYS),
	localparam int ADDR_W  = $clog2(ENTRIES)
) (
	input  logic clk_i,
	input  logic rst_ni,

	// TODO: add invalidation

	input  logic [ ADDR_W-1:0] r_addr_i,
	output logic [ENTBITS-1:0] lru_way_o,

	input  logic               use_i,
	input  logic [ENTBITS-1:0] use_way_i,
	input  logic [ ADDR_W-1:0] use_addr_i
);

	// True LRU implemented as promotion queue
	// Used items are put at address 0, address 3 is LRU

	logic [WAYS*ENTBITS-1:0] entries     [ENTRIES-1:0];
	logic                    initialized [ENTRIES-1:0];
	logic [WAYS*ENTBITS-1:0] used_line, write_line, default_line;

	logic [WAYS-1:0] use_mask, shift_mask;

	initial entries = '{default: '0};
	initial initialized = '{default: '0};

	/* Line + mask generation */

	assign used_line = initialized[use_addr_i] ? entries[use_addr_i] : default_line;

	generate
		for (genvar i = 0; i < WAYS; i++) begin : gen_ways
			assign use_mask[i] = used_line[i*ENTBITS+:ENTBITS] == use_way_i;
			assign shift_mask[i] = |use_mask[WAYS-1:i];
			assign default_line[i*ENTBITS +: ENTBITS] = ENTBITS'(WAYS-i-1);
		end : gen_ways

		assign write_line[0+:ENTBITS] = use_way_i;
		for (genvar i = 1; i < WAYS; i++) begin : gen_write_line
			assign write_line[ENTBITS*i+:ENTBITS] = shift_mask[i]
				? used_line[ENTBITS*(i-1)+:ENTBITS]
				: used_line[ENTBITS*i+:ENTBITS];
		end : gen_write_line
	endgenerate


	/* Memory inference */

	always_ff @(posedge clk_i) begin
		if (use_i) entries[use_addr_i] <= write_line;
		if (use_i) initialized[use_addr_i] <= '1;
	end

	// To reduce timing pressure, r_addr_i is buffered before reading.
	// (instead of reading asynchronously and buffering the read value)
	logic [ADDR_W-1:0] r_addr_q;

	always_ff @(posedge clk_i or negedge rst_ni) begin
		if (~rst_ni) begin
			r_addr_q <= '0;
		end else begin
			r_addr_q <= r_addr_i;
		end
	end

	assign lru_way_o = initialized[r_addr_q] ? entries[r_addr_q][(WAYS-1)*ENTBITS+:ENTBITS] : '0;

endmodule
