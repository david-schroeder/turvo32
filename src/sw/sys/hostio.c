// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: David Schröder 2026

#include <stdio.h>
#include <stdint.h>

static uint8_t *textbuf = (uint8_t *)0x100;

static size_t
stdin_read(FILE *fp, char *bp, size_t n) {
    return 0;
}

static size_t
stdout_write(FILE *fp, const char *bp, size_t n) {
    while (n-- > 0) {
        *(--textbuf) = *(bp++);
    }
    return n;
}

static struct File_methods _hostio_methods = {
    .write = stdout_write,
    .read = stdin_read
};
static struct File _hostio = {
    .vmt = &_hostio_methods
};

struct File *const stdin = &_hostio;
struct File *const stdout = &_hostio;
struct File *const stderr = &_hostio;
