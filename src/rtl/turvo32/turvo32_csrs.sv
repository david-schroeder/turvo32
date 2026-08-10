// SPDX-License-Identifier: SHL-2.1
// SPDX-FileCopyrightText: David Schröder 2026

// RISC-V Control and Status Registers.

module turvo32_csrs
    import turvo32_pkg::*;
(
    input  logic clk_i,
    input  logic rst_ni,

    // Software interface
    input  logic        read_en_i,
    input  logic        write_en_i,
    input  csr_e        csr_sel_i,
    input  csr_op_e     op_i,
    input  logic [31:0] operand_i,
    output logic [31:0] rdata_o,

    // Trap management
    input  logic [31:0] ext_ints_i,
    input  logic        trap_i,
    input  mcause_t     trap_cause_i,
    input  logic [31:0] trap_val_i,
    input  logic [31:0] epc_i,
    input  logic        mret_i,

    // Direct CSR outputs
    output mstatus_t    mstatus_o,
    output logic [31:0] mie_o,
    output logic [31:0] mip_o,
    output mtvec_t      mtvec_o,
    output logic [31:0] mepc_o,

    // Performance counters
    input  logic        commit_i // whether to increment mcycle
);

    mstatus_t    mstatus_d,  mstatus_q;
    mtvec_t      mtvec_d,    mtvec_q;
    logic [31:0] mie_d,      mie_q;
    logic [31:0] mip_d,      mip_q;
    logic [31:0] mscratch_d, mscratch_q;
    logic [31:1] mepc_d,     mepc_q;
    mcause_t     mcause_d,   mcause_q;
    logic [31:0] mtval_d,    mtval_q;
    logic [63:0] mcycle_d,   mcycle_q;
    logic [63:0] minstret_d, minstret_q;

    logic [63:0] minstret_incr;
    assign minstret_incr = minstret_q + commit_i;

    assign mstatus_o = mstatus_q;
    assign mie_o     = mie_q;
    assign mip_o     = mip_q;
    assign mtvec_o   = mtvec_q;
    assign mepc_o    = {mepc_q, 1'b0};

    logic [31:0] csr_wdata;
    always_comb begin
        unique case (op_i)
            CSRRW: csr_wdata = operand_i;
            CSRRS: csr_wdata = rdata_o | operand_i;
            CSRRC: csr_wdata = rdata_o & (~operand_i);
        endcase
    end

    always_comb begin
        mstatus_d  = mstatus_q;
        mtvec_d    = mtvec_q;
        mie_d      = mie_q;
        mip_d      = mip_q | ext_ints_i;
        mscratch_d = mscratch_q;
        mepc_d     = mepc_q;
        mcause_d   = mcause_q;
        mtval_d    = mtval_q;
        mcycle_d   = mcycle_q + 1;
        // commit comes from WB stage
        minstret_d = minstret_incr;

        if (write_en_i) begin
            unique case (csr_sel_i)
                MSTATUS: mstatus_d = '{
                    mpp: M_MODE,
                    mie: csr_wdata[3],
                    mpie: csr_wdata[7]
                };
                MIE: mie_d = csr_wdata;
                MIP: mip_d = csr_wdata;
                MTVEC: mtvec_d = '{base: csr_wdata[31:2], mode: csr_wdata[0]};
                MSCRATCH: mscratch_d = csr_wdata;
                MEPC: mepc_d = csr_wdata[31:1];
                MCAUSE: mcause_d = '{
                    interrupt: csr_wdata[31],
                    cause: exc_cause_e'(csr_wdata[4:0])
                };
                MTVAL: mtval_d = csr_wdata;
                MCYCLE: mcycle_d[31:0] = csr_wdata;
                MCYCLEH: mcycle_d[63:32] = csr_wdata;
                MINSTRET: minstret_d[31:0] = csr_wdata;
                MINSTRETH: minstret_d[63:32] = csr_wdata;
                default: ;
            endcase
        end

        if (trap_i) begin
            mepc_d = epc_i[31:1];
            mcause_d = trap_cause_i;
            mtval_d = trap_val_i;
            mstatus_d = '{
                mpp: M_MODE,
                mpie: mstatus_q.mie,
                mie: '0
            };
        end else if (mret_i) begin
            mstatus_d = '{
                mpp: M_MODE,
                mpie: '1,
                mie: mstatus_q.mpie
            };
        end
    end

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (~rst_ni) begin
            mstatus_q  <= '{mpp: M_MODE, default: '0};
            mtvec_q    <= '{default: '0};
            mie_q      <= '0;
            mip_q      <= '0;
            mscratch_q <= '0;
            mepc_q     <= '0;
            mcause_q   <= INSN_ADDR_MISALIGNED;
            mtval_q    <= '0;
            mcycle_q   <= '0;
            minstret_q <= '0;
        end else begin
            mstatus_q  <= mstatus_d;
            mtvec_q    <= mtvec_d;
            mie_q      <= mie_d;
            mip_q      <= mip_d;
            mscratch_q <= mscratch_d;
            mepc_q     <= mepc_d;
            mcause_q   <= mcause_d;
            mtval_q    <= mtval_d;
            mcycle_q   <= mcycle_d;
            minstret_q <= minstret_d;
        end
    end

    /* Read logic */
    always_comb begin
        rdata_o = '0;
        if (read_en_i) begin
            unique case (csr_sel_i)
                MSTATUS: rdata_o = {
                    19'h0,
                    mstatus_q.mpp,
                    3'h0,
                    mstatus_q.mpie,
                    3'h0,
                    mstatus_q.mie,
                    3'h0
                };
                MIE: rdata_o = mie_q;
                MIP: rdata_o = mip_q;
                MTVEC: rdata_o = {mtvec_q.base, 1'b0, mtvec_q.mode};
                MSCRATCH: rdata_o = mscratch_q;
                MEPC: rdata_o = {mepc_q[31:1], 1'b0};
                MCAUSE: rdata_o = {mcause_q.interrupt, 26'h0, mcause_q.cause};
                MTVAL: rdata_o = mtval_q;
                MCYCLE: rdata_o = mcycle_q[31:0];
                MCYCLEH: rdata_o = mcycle_q[63:32];
                MINSTRET: rdata_o = minstret_incr[31:0];
                MINSTRETH: rdata_o = minstret_incr[63:32];
                default: rdata_o = '0;
            endcase
        end
    end

endmodule
