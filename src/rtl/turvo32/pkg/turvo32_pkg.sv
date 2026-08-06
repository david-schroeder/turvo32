package turvo32_pkg;

    typedef enum logic [2:0] {
        ADD,
        SUB,
        XOR,
        AND,
        OR,
        SLT,
        SLTU
    } alu_op_e;

    typedef enum logic [1:0] {
        RS1,
        PC,
        ZERO
    } alu_src1_e;

    typedef enum logic [0:0] {
        RS2,
        IMM
    } alu_src2_e;

    typedef enum logic [1:0] {
        SLL,
        SRL,
        SRA
    } shift_op_e;

    typedef enum logic [1:0] {
        MUL,
        MULH,
        MULHSU,
        MULHU
    } mult_op_e;

    typedef enum logic [1:0] {
        DIV,
        DIVU,
        REM,
        REMU
    } div_op_e;

    typedef enum logic [2:0] {
        LB,
        LBU,
        LH,
        LHU,
        LW,
        SB,
        SH,
        SW
    } mem_op_e;

    typedef enum logic [2:0] {
        R_TYPE,
        I_TYPE,
        S_TYPE,
        B_TYPE,
        U_TYPE,
        J_TYPE
    } instr_type_e;

    typedef enum logic [2:0] {
        ALU,
        SHIFTER,
        LSU,
        SEQ_PC,
        CSR,
        MULT,
        DIVIDER
    } wb_src_e;

    typedef enum logic [2:0] {
        BEQ,
        BNE,
        BLT,
        BGE,
        BLTU,
        BGEU
    } branch_e;

    typedef enum logic [1:0] {
        CSRRW,
        CSRRS,
        CSRRC
    } csr_op_e;

    typedef enum logic [11:0] {
        MSTATUS   = 12'h300,
        MIE       = 12'h304,
        MTVEC     = 12'h305,
        MSCRATCH  = 12'h340,
        MEPC      = 12'h341,
        MCAUSE    = 12'h342,
        MTVAL     = 12'h343,
        MIP       = 12'h344,
        MCYCLE    = 12'hB00,
        MINSTRET  = 12'hB02,
        MCYCLEH   = 12'hB80,
        MINSTRETH = 12'hB82
    } csr_e;

    typedef enum logic [1:0] {
        M_MODE = 2'b11,
        S_MODE = 2'b01,
        U_MODE = 2'b00
    } priv_lvl_e;

    typedef struct packed {
        priv_lvl_e mpp;
        logic      mpie;
        logic      mie;
    } mstatus_t;

    typedef struct packed {
        logic [31:2] base;
        logic        mode;
    } mtvec_t;

    typedef enum logic [4:0] {
        INSN_ADDR_MISALIGNED  = 5'd0,
        INSN_ACCESS_FAULT     = 5'd1,
        ILLEGAL_INSN          = 5'd2,
        BREAKPOINT            = 5'd3,
        LOAD_ADDR_MISALIGNED  = 5'd4,
        LOAD_ACCESS_FAULT     = 5'd5,
        STORE_ADDR_MISALIGNED = 5'd6,
        STORE_ACCESS_FAULT    = 5'd7,
        ECALL_UMODE           = 5'd8,
        ECALL_SMODE           = 5'd9,
        ECALL_MMODE           = 5'd11,
        INSN_PAGE_FAULT       = 5'd12,
        LOAD_PAGE_FAULT       = 5'd13,
        STORE_PAGE_FAULT      = 5'd15,
        DOUBLE_TRAP           = 5'd16,
        SOFTWARE_CHECK        = 5'd18,
        HARDWARE_ERROR        = 5'd19
    } exc_cause_e;

    typedef struct packed {
        logic       interrupt;
        exc_cause_e cause;
    } mcause_t;

    typedef struct packed {
        logic [31:0] address;
        logic [31:0] mask;
        logic        idempotent;
    } pma_region_t;

    /* Platform-level parameters */

    parameter int NUM_PMA_REGIONS = 1;
    parameter pma_region_t PMA_REGIONS [NUM_PMA_REGIONS-1:0] = '{
        // 128KiB main BRAM
        '{ address: 32'h00000000, mask: 32'hFFFF8000, idempotent: '1 }
    };

endpackage
