#include <stdlib.h>

#include "zpb.h"
#include "zpb_build.h"

/* proto_decode()'s C half (design sections 4, 12 and 13). The message is
 * decoded into an arena whose allocator caps its size, and the arena is
 * owned by a finalised external pointer from the moment it exists, so an
 * interrupt or allocation failure while R values are built frees it. On
 * success it is freed eagerly. */

typedef struct {
    zpb_counting_alloc alloc; /* must outlive the arena it backs */
    zpb_arena *arena;
} decode_holder;

static void holder_finalize(SEXP ptr)
{
    decode_holder *h = (decode_holder *) R_ExternalPtrAddr(ptr);
    if (h == NULL) return;
    if (h->arena != NULL) zpb_arena_free(h->arena);
    free(h);
    R_ClearExternalPtr(ptr);
}

static SEXP result(SEXP value, const char *error, const char *field,
                   double precision_loss, double unknown_enum)
{
    const char *names[] = {"value", "error", "field", "precision_loss",
                           "unknown_enum", ""};
    PROTECT(value);
    SEXP out = PROTECT(Rf_mkNamed(VECSXP, names));
    SET_VECTOR_ELT(out, 0, value);
    SET_VECTOR_ELT(out, 1, error ? Rf_mkString(error) : R_NilValue);
    SET_VECTOR_ELT(out, 2, field ? Rf_mkString(field) : R_NilValue);
    SET_VECTOR_ELT(out, 3, Rf_ScalarReal(precision_loss));
    SET_VECTOR_ELT(out, 4, Rf_ScalarReal(unknown_enum));
    UNPROTECT(2);
    return out;
}

static int opt_int(SEXP opts, const char *name)
{
    SEXP names = Rf_getAttrib(opts, R_NamesSymbol);
    for (R_xlen_t i = 0; i < XLENGTH(opts); i++)
        if (strcmp(CHAR(STRING_ELT(names, i)), name) == 0)
            return Rf_asInteger(VECTOR_ELT(opts, i));
    Rf_error("zuproto: missing decode option '%s'", name);
}

static double opt_real(SEXP opts, const char *name)
{
    SEXP names = Rf_getAttrib(opts, R_NamesSymbol);
    for (R_xlen_t i = 0; i < XLENGTH(opts); i++)
        if (strcmp(CHAR(STRING_ELT(names, i)), name) == 0)
            return Rf_asReal(VECTOR_ELT(opts, i));
    Rf_error("zuproto: missing decode option '%s'", name);
}

/* Decode raw as message type `type` of pool. Returns list(value, error,
 * field, precision_loss, unknown_enum); R/decode.R raises or warns. error
 * is NULL on success, else one of "unknown_type", "malformed",
 * "max_depth", "invalid_utf8", "arena_limit", "out_of_memory", "other",
 * "nul_in_string" or "string_too_long". */
SEXP zpb_decode(SEXP ptr, SEXP type, SEXP raw, SEXP opts)
{
    const zpb_defpool *pool = zpb_pool_get(ptr);
    const zpb_msgdef *m =
        zpb_defpool_find_message(pool, Rf_translateCharUTF8(STRING_ELT(type, 0)));
    if (m == NULL) return result(R_NilValue, "unknown_type", NULL, 0, 0);

    zpb_build_ctx ctx = {0};
    ctx.pool = pool;
    ctx.int64 = opt_int(opts, "int64");
    ctx.enums = opt_int(opts, "enums");
    ctx.defaults = opt_int(opts, "defaults");
    ctx.keep_unknown = opt_int(opts, "keep_unknown");
    ctx.bytes_base64 = opt_int(opts, "bytes_base64");
    int max_depth = opt_int(opts, "max_depth");
    double arena_limit = opt_real(opts, "arena_limit");

    decode_holder *h = (decode_holder *) calloc(1, sizeof *h);
    if (h == NULL) Rf_error("zuproto: out of memory");
    SEXP hptr = PROTECT(R_MakeExternalPtr(h, R_NilValue, R_NilValue));
    R_RegisterCFinalizerEx(hptr, holder_finalize, TRUE);
    h->arena = zpb_arena_new_limited(&h->alloc, (size_t) arena_limit);
    if (h->arena == NULL) {
        holder_finalize(hptr);
        UNPROTECT(1);
        return result(R_NilValue, "arena_limit", NULL, 0, 0);
    }

    int status;
    const zpb_msg *msg = zpb_decode_message(
        pool, m, (const char *) RAW(raw), (size_t) XLENGTH(raw), h->arena,
        (uint16_t) max_depth, &status);
    if (msg == NULL) {
        const char *err = status == ZPB_DECODE_MALFORMED ? "malformed"
                          : status == ZPB_DECODE_DEPTH   ? "max_depth"
                          : status == ZPB_DECODE_UTF8    ? "invalid_utf8"
                          : status == ZPB_DECODE_MEMORY
                              ? (h->alloc.exceeded ? "arena_limit" : "out_of_memory")
                              : "other";
        holder_finalize(hptr);
        UNPROTECT(1);
        return result(R_NilValue, err, NULL, 0, 0);
    }

    SEXP value = zpb_build(&ctx, m, msg);
    if (value == NULL) {
        const char *err =
            ctx.err == ZPB_BUILD_ERR_NUL ? "nul_in_string" : "string_too_long";
        /* err_field points into the pool, which outlives the arena. */
        holder_finalize(hptr);
        UNPROTECT(1);
        return result(R_NilValue, err, ctx.err_field, 0, 0);
    }
    PROTECT(value);
    holder_finalize(hptr);
    SEXP out = result(value, NULL, NULL, ctx.precision_loss, ctx.unknown_enum);
    UNPROTECT(2);
    return out;
}
