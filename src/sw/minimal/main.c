/* SPDX-License-Identifier: Apache-2.0
 * SPDX-FileCopyrightText: David Schröder 2026
 */

#include <stdio.h>
#include <stdint.h>

#define read_csr(reg) ({ unsigned long __tmp; \
    asm volatile ("csrr %0, " reg : "=r"(__tmp)); \
    __tmp; })

#define write_csr(reg, val) ({ \
    asm volatile ("csrw " reg ", %0" :: "rK"(val)); })

/*int main(void) {
    printf("Hello World %d!\n", 567);

    uint32_t mcycle = read_csr("mcycle");
    uint32_t minstret = read_csr("minstret");

    uint32_t cpi_x1k = (mcycle * 1000) / minstret;

    printf("CPI: %d.%03d\n", cpi_x1k/1000, cpi_x1k%1000);

    return 0;
}*/

static inline uint64_t bench_instret_delta(void) {
    uint32_t start, end;

    asm volatile (
        "csrr %0, minstret   \n\t"   // snapshot #1
        "addi t0, zero, 1    \n\t"   // instruction 1
        "addi t0, t0, 1      \n\t"   // instruction 2
        "lh t0, 0(t0)        \n\t"   // instruction 3
        "csrr %1, minstret   \n\t"   // snapshot #2
        : "=r"(start), "=r"(end)
        :
        : "t0"
    );

    return end - start;
}

int main(void) {
    uint32_t delta = bench_instret_delta();
    printf("Instructions retired: %u\n", delta);
    return 0;
}
