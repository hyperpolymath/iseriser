/* SPDX-License-Identifier: MPL-2.0
 * Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
 *
 * Golden-sample FFI stub — a minimal C implementation of the 12 Chapeliser
 * C-ABI functions that the generated Chapel wrapper calls via `extern proc`.
 *
 * Its only purpose is to let CI compile AND RUN the generated Chapel end to
 * end (see .github/workflows/provable.yml, chapel-golden job). It implements a
 * trivial "echo" workload: 8 fixed items, each processed by copying input to
 * output unchanged. This stands in for real user code so the generated
 * distribution/gather/store logic can be exercised by `chpl`.
 *
 * Symbol names here match the `extern proc c_*` declarations emitted by
 * src/codegen/chapel.rs. (In production the generated Zig bridge in
 * src/codegen/zig.rs provides these `c_*` symbols, delegating to user code.)
 */
#include <stddef.h>
#include <string.h>

/* Prototypes for the c_* ABI (also `require`d by the generated Chapel). */
#include "echo_abi.h"

#define ECHO_ITEMS 8
#define ECHO_PAYLOAD 4

/* Lifecycle ---------------------------------------------------------------- */
int c_init(void) { return 0; }
int c_shutdown(void) { return 0; }

/* Data I/O ----------------------------------------------------------------- */
int c_get_total_items(void) { return ECHO_ITEMS; }

int c_load_item(int idx, unsigned char *buf, size_t *len) {
    if (idx < 0 || idx >= ECHO_ITEMS) return 2; /* invalid_param */
    if (*len < ECHO_PAYLOAD) return 3;          /* out_of_memory */
    for (size_t k = 0; k < ECHO_PAYLOAD; ++k)
        buf[k] = (unsigned char)(idx + (int)k);
    *len = ECHO_PAYLOAD;
    return 0;
}

int c_store_result(int idx, unsigned char *buf, size_t len) {
    (void)idx; (void)buf; (void)len;
    return 0;
}

/* Processing --------------------------------------------------------------- */
int c_process_item(unsigned char *in_buf, size_t in_len,
                   unsigned char *out_buf, size_t *out_len) {
    memcpy(out_buf, in_buf, in_len); /* echo */
    *out_len = in_len;
    return 0;
}

int c_process_chunk(unsigned char *items_buf, int item_count,
                    int *item_offsets, int *item_sizes,
                    unsigned char *out_buf, size_t *out_len) {
    (void)items_buf; (void)item_count; (void)item_offsets; (void)item_sizes;
    (void)out_buf;
    *out_len = 0;
    return 0;
}

/* Reduction ---------------------------------------------------------------- */
int c_reduce(unsigned char *a_buf, size_t a_len,
             unsigned char *b_buf, size_t b_len,
             unsigned char *out_buf, size_t *out_len) {
    memcpy(out_buf, a_buf, a_len);
    memcpy(out_buf + a_len, b_buf, b_len);
    *out_len = a_len + b_len;
    return 0;
}

/* Match predicate (for 'first' gather) ------------------------------------- */
int c_is_match(unsigned char *buf, size_t len) {
    (void)buf; (void)len;
    return 0;
}

/* Key hash (for keyed partition) ------------------------------------------- */
unsigned int c_key_hash(unsigned char *buf, size_t len) {
    (void)buf; (void)len;
    return 0u;
}

/* Checkpoint (optional — not implemented in the stub) ---------------------- */
int c_checkpoint_save(unsigned char *buf, size_t len, const char *tag) {
    (void)buf; (void)len; (void)tag;
    return -1;
}

int c_checkpoint_load(unsigned char *buf, size_t *len, const char *tag) {
    (void)buf; (void)len; (void)tag;
    return -1;
}
