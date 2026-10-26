/*
 * Shared by the libFuzzer targets in tools/fuzz (design section 15). The
 * upb targets compile the vendored upb and the shim with no R; fuzz_build
 * embeds R to reach the code that builds R values.
 *
 * FUZZ_CHECK fails the run on a broken invariant. FUZZ_CANARY, compiled in
 * with -DZPB_FUZZ_CANARY, writes out of bounds on the input "ZPB-CANARY":
 * running a canary build on that input must crash, which proves the
 * instrumentation is live.
 */
#ifndef ZPB_FUZZ_H
#define ZPB_FUZZ_H

#include <stddef.h>
#include <stdint.h>
#include <string.h>

#define FUZZ_CHECK(cond) do { if (!(cond)) __builtin_trap(); } while (0)

#ifdef ZPB_FUZZ_CANARY
#  define FUZZ_CANARY(data, size)                                        \
     do {                                                                \
         if ((size) == 10 && memcmp((data), "ZPB-CANARY", 10) == 0) {    \
             volatile char small[4];                                     \
             volatile char *volatile p = small;                          \
             volatile size_t i = (size);                                 \
             p[i] = 1; /* past the end: ASan's stack-buffer-overflow */  \
         }                                                               \
     } while (0)
#else
#  define FUZZ_CANARY(data, size) ((void)0)
#endif

/* The message types the targets decode, chosen by the input's first byte.
 * They cover every field kind (tests/testthat/fixtures/proto/decode*.proto)
 * and the well-known types. */
static const char *const zpb_fuzz_types[] = {
    "zpb.decode.Scalars",   "zpb.decode.Repeated", "zpb.decode.Maps",
    "zpb.decode.Choice",    "zpb.decode.WellKnown", "zpb.decode.Nested",
    "zpb.decode2.Legacy",   "google.protobuf.Struct", "google.protobuf.Value",
    "google.protobuf.Any",  "google.protobuf.Timestamp",
    "google.protobuf.FileDescriptorSet", "google.protobuf.Duration",
    "zpb.decode.Point",     "zpb.decode.Uint64Keys", "zpb.decode.Outer"};
#define ZPB_FUZZ_NTYPES (sizeof zpb_fuzz_types / sizeof zpb_fuzz_types[0])

/* The serialised descriptor set behind them (tools/fuzz/data.h). */
extern const unsigned char zpb_fuzz_descriptors[];
extern const size_t zpb_fuzz_descriptors_len;

#endif
