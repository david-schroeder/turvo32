// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: David Schröder 2026

    .section .text.boot
    .option push

    // IVT
    .option norvc
    .org 0
    j trap_handler  //  0
    nop             //  1
    j ext_handler   //  2
    nop             //  3
    nop             //  4
    nop             //  5
    nop             //  6
    nop             //  7
    nop             //  8
    nop             //  9
    j irq_error     // 10
    j ext_handler   // 11
    nop             // 12
    nop             // 13
    nop             // 14
    nop             // 15
    nop             // 16
    nop             // 17
    nop             // 18
    nop             // 19
    nop             // 20
    nop             // 21
    nop             // 22
    nop             // 23
    nop             // 24
    nop             // 25
    nop             // 26
    nop             // 27
    nop             // 28
    nop             // 29
    nop             // 30
    j irq_error     // 31
    j _start        // 32: Reset vector / global entry point

    // Startup
    .option pop
    .global _start

_start:
    li  x1, 0
    la  sp, _main_stack_top
    li  x3, 0
    li  x4, 0
    li  x5, 0
    li  x6, 0
    li  x7, 0
    li  x8, 0
    li  x9, 0
    li  x10,0
    li  x11,0
    li  x12,0
    li  x13,0
    li  x14,0
    li  x15,0
    li  x16,0
    li  x17,0
    li  x18,0
    li  x19,0
    li  x20,0
    li  x21,0
    li  x22,0
    li  x23,0
    li  x24,0
    li  x25,0
    li  x26,0
    li  x27,0
    li  x28,0
    li  x29,0
    li  x30,0
    li  x31,0

    // Initialize various stack pointers, settings / CSRs etc. here
    la t0, _irq_stack_top
    csrrw t0, mscratch, t0 // irq stack top

    li t0, 2048   // machine external interrupt
    ori t0, t0, 4 // machine software interrupt
    csrw mie, t0  // enable selected interrupts

    csrsi mtvec, 1   // enabled vectored interrupts
    csrsi mstatus, 8 // global interrupt enable

    jal main

    csrci mstatus, 8 // global interrupt disable

_exit:
    // Set flags / communicate with host system here
    j end_loop

trap_handler:
    csrrw sp, mscratch, sp
    sw t0, -4(sp)

    // skip excepting instruction
    csrr t0, mepc
    addi t0, t0, 4
    csrw mepc, t0

    lw t0, -4(sp)
    csrrw sp, mscratch, sp
    mret

irq_error:
end_loop:
    j end_loop

ext_handler:
    csrw mip, zero
    mret
