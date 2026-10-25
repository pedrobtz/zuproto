#ifndef ZPB_BUILD_H
#define ZPB_BUILD_H

#include "zpb_upb.h"

/* Options and state of one decode (design section 5). */
enum { ZPB_INT64_DOUBLE = 0, ZPB_INT64_CHARACTER };
enum { ZPB_ENUMS_FACTOR = 0, ZPB_ENUMS_INTEGER, ZPB_ENUMS_CHARACTER };
enum {
    ZPB_BUILD_ERR_NONE = 0,
    ZPB_BUILD_ERR_NUL,         /* a string holds a NUL byte */
    ZPB_BUILD_ERR_LONG_STRING  /* a string is longer than R allows */
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

/* m's message msg as an R value, or NULL with ctx->err set. */
SEXP zpb_build(zpb_build_ctx *ctx, const zpb_msgdef *m, const zpb_msg *msg);

#endif
