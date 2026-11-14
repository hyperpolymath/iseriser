/* SPDX-License-Identifier: MPL-2.0 */
/* Subset of stdlib.h for atsiser safe-malloc example.
 *
 * These are the standard C memory allocation functions that atsiser wraps
 * with ATS2 linear types to provide compile-time memory safety guarantees.
 */

#ifndef STDLIB_SUBSET_H
#define STDLIB_SUBSET_H

#include <stddef.h>

/* Allocate SIZE bytes of memory. Returns a pointer that MUST be freed. */
void* malloc(size_t size);

/* Free a block allocated by malloc/realloc. Pointer MUST NOT be used after. */
void free(void* ptr);

/* Re-allocate a block to NEW_SIZE bytes. Old pointer is CONSUMED. */
void* realloc(void* ptr, size_t new_size);

/* Copy N bytes from SRC to DEST. Both pointers are BORROWED (not consumed). */
void* memcpy(void* dest, const void* src, size_t n);

/* Set N bytes of DEST to VALUE. Pointer is BORROWED. */
void* memset(void* dest, int value, size_t n);

#endif /* STDLIB_SUBSET_H */
