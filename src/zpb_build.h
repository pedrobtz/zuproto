#ifndef ZPB_BUILD_H
#define ZPB_BUILD_H

#include "zpb_upb.h"

/* Options and state of one decode (design section 5). */
enum { ZPB_INT64_DOUBLE = 0, ZPB_INT64_CHARACTER, ZPB_INT64_INTEGER64 };
enum { ZPB_ENUMS_FACTOR = 0, ZPB_ENUMS_INTEGER, ZPB_ENUMS_CHARACTER };
enum {
    ZPB_BUILD_ERR_NONE = 0,
    ZPB_BUILD_ERR_NUL,         /* a string holds a NUL byte */
    ZPB_BUILD_ERR_LONG_STRING, /* a string is longer than R allows */
    ZPB_BUILD_ERR_LONG_FRAME   /* a nested data frame has 2^31 rows or more */
};

typedef struct {
    const zpb_defpool *pool;
    int int64;
    int enums;
    int defaults;
    int keep_unknown;
    int bytes_base64;
    /* Counted while building; R warns once per decode. */
    double precision_loss;
    double unknown_enum;
    /* Set when building fails; the builders then return NULL. */
    int err;
    const char *err_field;
} zpb_build_ctx;

/* The symbol table behind a pool's external pointer (zpb_pool.c). */
const zpb_defpool *zpb_pool_get(SEXP ptr);

/* Its cache of arena ceilings, or NULL (zpb_pool.c). */
zpb_ceilings *zpb_pool_ceilings(SEXP ptr);

/* CHARSXP c as UTF-8 for upb (zpb_fill.c): 0, with *s set to text that
 * lives until the .Call returns; ZPB_TEXT_BYTES for a string marked as
 * bytes; ZPB_TEXT_INVALID for UTF-8 that is not valid; ZPB_TEXT_NATIVE for
 * a string the native encoding cannot read. */
enum { ZPB_TEXT_BYTES = 1, ZPB_TEXT_INVALID, ZPB_TEXT_NATIVE };
int zpb_char_utf8(SEXP c, const char **s);

/* m's message msg as an R value, or NULL with ctx->err set. */
SEXP zpb_build(zpb_build_ctx *ctx, const zpb_msgdef *m, const zpb_msg *msg);

/* A data frame with one row per message of type m (rows[i] NULL: a row of
 * NA), or NULL with ctx->err set. */
SEXP zpb_build_frame(zpb_build_ctx *ctx, const zpb_msgdef *m, const zpb_msg **rows,
                     R_xlen_t n);

#endif
