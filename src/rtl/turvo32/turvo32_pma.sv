// SPDX-License-Identifier: SHL-2.1
// SPDX-FileCopyrightText: David Schröder 2026

// Physical Memory Attribute Region Decoder.

module turvo32_pma
	import turvo32_pkg::*;
#(
	// Default to platform values from turvo32_pkg
	parameter int NREGIONS = NUM_PMA_REGIONS,
	parameter pma_region_t REGIONS [NREGIONS-1:0] = PMA_REGIONS
) (
	input  logic [31:0] address_i,
	output logic        valid_o,
	output logic        idempotent_o
);

	pma_region_t selected_region;

	always_comb begin
		selected_region = REGIONS[0];
		valid_o = '0;

		for (int i = 0; i < NREGIONS; i++) begin
			if ((address_i & REGIONS[i].mask) == REGIONS[i].address) begin
				selected_region = REGIONS[i];
				valid_o = '1;
			end
		end
	end

	assign idempotent_o = selected_region.idempotent;

endmodule
