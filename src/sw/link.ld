/* SPDX-License-Identifier: Apache-2.0
 * SPDX-FileCopyrightText: David Schröder 2026
 */

OUTPUT_ARCH( "riscv" )
ENTRY(_start)

SECTIONS
{
  . = 0x00000000;

  .text.boot : { *(.text.boot) }

  . = ALIGN(4);

  .text.lib : { *libsys.a:*(.text .text.*) }
  .rodata.lib : { *libsys.a:*(.rodata .rodata.* .sdata .sdata.* .srodata .srodata.*) }
  .data.lib : { *libsys.a:*(.data .data.*) }
  .bss.lib : { *libsys.a:*(.bss .sbss) }

  .text : { *(.text .text.*) }
  .rodata : { *(.rodata .rodata.* .sdata .sdata.* .srodata .srodata.*)  }
  .data : { *(.data .data.*) }
  .bss : { *(.bss .sbss) }

  /DISCARD/ : { *(.eh_frame*) }

  /* Adjust for your software system */
  _main_stack_top = 0x0001EFFC;
  _irq_stack_top = 0x0001FFF0;
}
