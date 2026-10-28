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
    zpb_internal_error("missing decode option '%s'", name);
}

static double opt_real(SEXP opts, const char *name)
{
    SEXP names = Rf_getAttrib(opts, R_NamesSymbol);
    for (R_xlen_t i = 0; i < XLENGTH(opts); i++)
        if (strcmp(CHAR(STRING_ELT(names, i)), name) == 0)
            return Rf_asReal(VECTOR_ELT(opts, i));
    zpb_internal_error("missing decode option '%s'", name);
}

/* A ceiling as a size_t, saturating. */
static size_t size_cap(double limit)
{
    return limit >= (double) SIZE_MAX ? SIZE_MAX : (size_t) limit;
}

static const char *opt_str(SEXP opts, const char *name)
{
    SEXP names = Rf_getAttrib(opts, R_NamesSymbol);
    for (R_xlen_t i = 0; i < XLENGTH(opts); i++)
        if (strcmp(CHAR(STRING_ELT(names, i)), name) == 0)
            return Rf_translateCharUTF8(STRING_ELT(VECTOR_ELT(opts, i), 0));
    zpb_internal_error("missing decode option '%s'", name);
}

/* Decode raw as message type `type` of pool. Returns list(value, error,
 * field, precision_loss, unknown_enum); R/decode.R raises or warns. error
 * is NULL on success, else one of "unknown_type", "malformed",
 * "max_depth", "invalid_utf8", "arena_limit", "out_of_memory", "other",
 * "nul_in_string" or "string_too_long". */
SEXP zpb_decode(SEXP ptr, SEXP type, SEXP raw, SEXP opts)
{
    const zpb_defpool *pool = zpb_pool_get(ptr);
    zpb_ceilings *ceilings = zpb_pool_ceilings(ptr);
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
    /* The ceiling comes from the schema (design section 12). */
    double arena_limit = zpb_arena_ceiling(pool, ceilings, m, (double) XLENGTH(raw), 1);

    decode_holder *h = (decode_holder *) calloc(1, sizeof *h);
    if (h == NULL) zpb_internal_error("out of memory");
    SEXP hptr = PROTECT(R_MakeExternalPtr(h, R_NilValue, R_NilValue));
    R_RegisterCFinalizerEx(hptr, holder_finalize, TRUE);
    h->arena = zpb_arena_new_limited(&h->alloc, size_cap(arena_limit));
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

/* ---- Many messages (design sections 6.4 and 10) ---- */

static SEXP df_result(SEXP value, const char *error, const char *field, double index,
                      double consumed, double precision_loss, double unknown_enum)
{
    const char *names[] = {"value", "error", "field", "index", "consumed",
                           "precision_loss", "unknown_enum", ""};
    PROTECT(value);
    SEXP out = PROTECT(Rf_mkNamed(VECSXP, names));
    SET_VECTOR_ELT(out, 0, value);
    SET_VECTOR_ELT(out, 1, error ? Rf_mkString(error) : R_NilValue);
    SET_VECTOR_ELT(out, 2, field ? Rf_mkString(field) : R_NilValue);
    SET_VECTOR_ELT(out, 3, Rf_ScalarReal(index));
    SET_VECTOR_ELT(out, 4, Rf_ScalarReal(consumed));
    SET_VECTOR_ELT(out, 5, Rf_ScalarReal(precision_loss));
    SET_VECTOR_ELT(out, 6, Rf_ScalarReal(unknown_enum));
    UNPROTECT(2);
    return out;
}

static const char *decode_status_name(int status, const zpb_counting_alloc *ca)
{
    return status == ZPB_DECODE_MALFORMED ? "malformed"
           : status == ZPB_DECODE_DEPTH   ? "max_depth"
           : status == ZPB_DECODE_UTF8    ? "invalid_utf8"
           : status == ZPB_DECODE_MEMORY  ? (ca->exceeded ? "arena_limit" : "out_of_memory")
                                          : "other";
}

/* A varint at buf[*at], within len; -1 if the buffer ends inside it, -2 if
 * it runs past ten bytes. */
static int read_varint(const unsigned char *buf, size_t len, size_t *at, uint64_t *out)
{
    uint64_t v = 0;
    for (int shift = 0; shift < 70; shift += 7) {
        if (*at >= len) return -1;
        unsigned char b = buf[(*at)++];
        v |= (uint64_t) (b & 0x7f) << shift;
        if (!(b & 0x80)) {
            *out = v;
            return 0;
        }
    }
    return -2;
}

/* proto_decode_df(), proto_read_delimited(). mode 0: x is a list of raw
 * vectors, one message each. mode 1: x is one message, and the rows are the
 * elements of its repeated message field `field`. mode 2: x is a
 * length-delimited buffer; whole messages are decoded, at most chunk_rows
 * of them, and `consumed` says how many bytes they took, so the caller can
 * keep the rest for the next chunk. Returns the data frame, or an error
 * with `index`, the 1-based position of the message at fault. */
SEXP zpb_decode_df(SEXP ptr, SEXP type, SEXP x, SEXP opts)
{
    const zpb_defpool *pool = zpb_pool_get(ptr);
    zpb_ceilings *ceilings = zpb_pool_ceilings(ptr);
    const zpb_msgdef *m =
        zpb_defpool_find_message(pool, Rf_translateCharUTF8(STRING_ELT(type, 0)));
    if (m == NULL) return df_result(R_NilValue, "unknown_type", NULL, 0, 0, 0, 0);

    zpb_build_ctx ctx = {0};
    ctx.pool = pool;
    ctx.int64 = opt_int(opts, "int64");
    ctx.enums = opt_int(opts, "enums");
    ctx.defaults = opt_int(opts, "defaults");
    ctx.bytes_base64 = opt_int(opts, "bytes_base64");
    int mode = opt_int(opts, "mode");
    int max_depth = opt_int(opts, "max_depth");
    double max_size = opt_real(opts, "max_size");
    double max_rows = opt_real(opts, "max_rows");
    double chunk_rows = opt_real(opts, "chunk_rows");
    /* The ceiling comes from the schema (design section 12): the input's
     * bytes, and the messages it can hold (each takes a byte of length
     * prefix in a stream). */
    double input = 0, n_msgs = 1;
    if (mode == 0) {
        for (R_xlen_t i = 0; i < XLENGTH(x); i++) input += (double) XLENGTH(VECTOR_ELT(x, i));
        n_msgs = (double) XLENGTH(x);
    } else {
        input = (double) XLENGTH(x);
        n_msgs = mode == 2 ? input : 1;
    }
    double arena_limit = zpb_arena_ceiling(pool, ceilings, m, input, n_msgs);

    decode_holder *h = (decode_holder *) calloc(1, sizeof *h);
    if (h == NULL) zpb_internal_error("out of memory");
    SEXP hptr = PROTECT(R_MakeExternalPtr(h, R_NilValue, R_NilValue));
    R_RegisterCFinalizerEx(hptr, holder_finalize, TRUE);
    h->arena = zpb_arena_new_limited(&h->alloc, size_cap(arena_limit));
    if (h->arena == NULL) {
        holder_finalize(hptr);
        UNPROTECT(1);
        return df_result(R_NilValue, "arena_limit", NULL, 0, 0, 0, 0);
    }

/* `err` is evaluated before the holder is freed: decode_status_name()
 * reads its allocator. */
#define FAIL(err, field, index, consumed)                                    \
    do {                                                                     \
        const char *fail_err = (err);                                        \
        holder_finalize(hptr);                                               \
        UNPROTECT(1);                                                        \
        return df_result(R_NilValue, fail_err, field, index, consumed, 0, 0); \
    } while (0)

    const zpb_msgdef *row_def = m;
    const zpb_msg **rows = NULL;
    R_xlen_t n = 0;
    double consumed = 0;
    int status;

    if (mode == 0) {
        n = XLENGTH(x);
        rows = n > 0 ? (const zpb_msg **) R_alloc((size_t) n, sizeof *rows) : NULL;
        for (R_xlen_t i = 0; i < n; i++) {
            if ((i & 0xfff) == 0xfff) R_CheckUserInterrupt();
            SEXP r = VECTOR_ELT(x, i);
            rows[i] = zpb_decode_message(pool, m, (const char *) RAW(r), (size_t) XLENGTH(r),
                                         h->arena, (uint16_t) max_depth, &status);
            if (rows[i] == NULL) FAIL(decode_status_name(status, &h->alloc), NULL, i + 1, 0);
        }
    } else if (mode == 1) {
        const char *fname = opt_str(opts, "field");
        const zpb_fielddef *f = zpb_msgdef_find_field(m, fname, strlen(fname));
        if (f == NULL || !zpb_field_is_repeated(f) || zpb_field_is_map(f) ||
            zpb_field_ctype(f) != ZPB_CTYPE_MESSAGE)
            FAIL("bad_field", NULL, 0, 0);
        const zpb_msg *msg = zpb_decode_message(pool, m, (const char *) RAW(x),
                                                (size_t) XLENGTH(x), h->arena,
                                                (uint16_t) max_depth, &status);
        if (msg == NULL) FAIL(decode_status_name(status, &h->alloc), NULL, 1, 0);
        const zpb_array *a = zpb_msg_get(msg, f).array_val;
        n = (R_xlen_t) zpb_array_size(a);
        if ((double) n > max_rows) FAIL("max_rows", NULL, 0, 0);
        rows = n > 0 ? (const zpb_msg **) R_alloc((size_t) n, sizeof *rows) : NULL;
        for (R_xlen_t i = 0; i < n; i++) rows[i] = zpb_array_get(a, (size_t) i).msg_val;
        row_def = zpb_field_msgdef(f);
    } else {
        const unsigned char *buf = RAW(x);
        size_t len = (size_t) XLENGTH(x), at = 0;
        size_t cap = 1024;
        rows = (const zpb_msg **) R_alloc(cap, sizeof *rows);
        while (at < len && (double) n < chunk_rows) {
            if ((n & 0xfff) == 0xfff) R_CheckUserInterrupt();
            size_t start = at;
            uint64_t size;
            int r = read_varint(buf, len, &at, &size);
            if (r == -2) FAIL("malformed", NULL, (double) n + 1, (double) start);
            if (r == -1) {
                at = start; /* ends inside a varint: leave it for the next chunk */
                break;
            }
            if ((double) size > max_size) FAIL("max_size", NULL, (double) n + 1, (double) start);
            if (size > len - at) {
                at = start; /* ends inside a message */
                break;
            }
            if ((double) n + 1 > max_rows) FAIL("max_rows", NULL, 0, (double) start);
            if ((size_t) n == cap) {
                const zpb_msg **grown = (const zpb_msg **) R_alloc(2 * cap, sizeof *rows);
                memcpy(grown, rows, cap * sizeof *rows);
                rows = grown;
                cap *= 2;
            }
            rows[n] = zpb_decode_message(pool, m, (const char *) buf + at, (size_t) size,
                                         h->arena, (uint16_t) max_depth, &status);
            if (rows[n] == NULL)
                FAIL(decode_status_name(status, &h->alloc), NULL, (double) n + 1, (double) start);
            at += (size_t) size;
            n++;
        }
        consumed = (double) at;
    }
#undef FAIL

    SEXP value = zpb_build_frame(&ctx, row_def, rows, n);
    if (value == NULL) {
        const char *err =
            ctx.err == ZPB_BUILD_ERR_NUL ? "nul_in_string" : "string_too_long";
        holder_finalize(hptr);
        UNPROTECT(1);
        return df_result(R_NilValue, err, ctx.err_field, 0, consumed, 0, 0);
    }
    PROTECT(value);
    holder_finalize(hptr);
    SEXP out = df_result(value, NULL, NULL, 0, consumed, ctx.precision_loss, ctx.unknown_enum);
    UNPROTECT(2);
    return out;
}

/* Raw messages joined as a length-delimited stream: each preceded by its
 * length as a varint. */
SEXP zpb_frame_delimited(SEXP msgs)
{
    R_xlen_t n = XLENGTH(msgs);
    double total = 0;
    for (R_xlen_t i = 0; i < n; i++) total += 10 + (double) XLENGTH(VECTOR_ELT(msgs, i));
    if (total > R_XLEN_T_MAX) zpb_internal_error("the stream would be too long for a raw vector");
    unsigned char *buf = (unsigned char *) R_alloc((size_t) total + 1, 1);
    size_t at = 0;
    for (R_xlen_t i = 0; i < n; i++) {
        SEXP r = VECTOR_ELT(msgs, i);
        uint64_t size = (uint64_t) XLENGTH(r);
        do {
            unsigned char b = size & 0x7f;
            size >>= 7;
            buf[at++] = size ? b | 0x80 : b;
        } while (size);
        if (XLENGTH(r) > 0) memcpy(buf + at, RAW(r), (size_t) XLENGTH(r));
        at += (size_t) XLENGTH(r);
    }
    SEXP out = PROTECT(Rf_allocVector(RAWSXP, (R_xlen_t) at));
    if (at > 0) memcpy(RAW(out), buf, at);
    UNPROTECT(1);
    return out;
}

/* ---- Protobuf JSON (design section 5) ---- */

static SEXP json_result(SEXP value, const char *error, const char *detail)
{
    const char *names[] = {"value", "error", "detail", ""};
    PROTECT(value);
    SEXP out = PROTECT(Rf_mkNamed(VECSXP, names));
    SET_VECTOR_ELT(out, 0, value);
    SET_VECTOR_ELT(out, 1, error ? Rf_mkString(error) : R_NilValue);
    SET_VECTOR_ELT(out, 2, detail ? Rf_mkString(detail) : R_NilValue);
    UNPROTECT(2);
    return out;
}

/* A capped arena owned by a finalised external pointer, PROTECTed. */
static SEXP new_holder(decode_holder **out, double limit)
{
    decode_holder *h = (decode_holder *) calloc(1, sizeof *h);
    if (h == NULL) zpb_internal_error("out of memory");
    SEXP hptr = PROTECT(R_MakeExternalPtr(h, R_NilValue, R_NilValue));
    R_RegisterCFinalizerEx(hptr, holder_finalize, TRUE);
    h->arena = zpb_arena_new_limited(&h->alloc, size_cap(limit));
    *out = h;
    return hptr;
}

/* proto_to_json(): binary message raw as protobuf JSON text. opts:
 * max_depth, json_options. */
SEXP zpb_to_json(SEXP ptr, SEXP type, SEXP raw, SEXP opts)
{
    const zpb_defpool *pool = zpb_pool_get(ptr);
    zpb_ceilings *ceilings = zpb_pool_ceilings(ptr);
    const zpb_msgdef *m =
        zpb_defpool_find_message(pool, Rf_translateCharUTF8(STRING_ELT(type, 0)));
    if (m == NULL) return json_result(R_NilValue, "unknown_type", NULL);

    decode_holder *h;
    SEXP hptr = new_holder(&h, zpb_arena_ceiling(pool, ceilings, m, (double) XLENGTH(raw), 1));
    if (h->arena == NULL) {
        holder_finalize(hptr);
        UNPROTECT(1);
        return json_result(R_NilValue, "arena_limit", NULL);
    }
    int status;
    int max_depth = opt_int(opts, "max_depth");
    const zpb_msg *msg = zpb_decode_message(pool, m, (const char *) RAW(raw),
                                            (size_t) XLENGTH(raw), h->arena,
                                            (uint16_t) max_depth, &status);
    /* upb's JSON encoder decodes packed Anys itself, unbounded: check them
     * first, within max_depth and the arena (zpb_check_any()). */
    if (msg != NULL) {
        status = zpb_check_any(pool, ceilings, m, msg, max_depth, h->arena, &h->alloc);
        if (status != ZPB_DECODE_OK) msg = NULL;
    }
    if (msg == NULL) {
        const char *err = decode_status_name(status, &h->alloc);
        holder_finalize(hptr);
        UNPROTECT(1);
        return json_result(R_NilValue, err, NULL);
    }
    int options = opt_int(opts, "json_options");
    char err[1024];
    size_t n = zpb_json_encode(msg, m, pool, options, NULL, 0, err, sizeof err);
    if (n == (size_t) -1 || n > INT_MAX) {
        holder_finalize(hptr);
        UNPROTECT(1);
        return json_result(R_NilValue, "json", n == (size_t) -1 ? err : "the JSON is longer than an R string may be");
    }
    char *buf = R_alloc(n + 1, 1);
    zpb_json_encode(msg, m, pool, options, buf, n + 1, err, sizeof err);
    holder_finalize(hptr);
    SEXP s = PROTECT(Rf_ScalarString(Rf_mkCharLenCE(buf, (int) n, CE_UTF8)));
    SEXP out = json_result(s, NULL, NULL);
    UNPROTECT(2);
    return out;
}

/* proto_from_json(): JSON text as binary, encoded deterministically. opts:
 * ignore_unknown, check_required. */
SEXP zpb_from_json(SEXP ptr, SEXP type, SEXP json, SEXP opts)
{
    const zpb_defpool *pool = zpb_pool_get(ptr);
    zpb_ceilings *ceilings = zpb_pool_ceilings(ptr);
    const zpb_msgdef *m =
        zpb_defpool_find_message(pool, Rf_translateCharUTF8(STRING_ELT(type, 0)));
    if (m == NULL) return json_result(R_NilValue, "unknown_type", NULL);

    const char *text = Rf_translateCharUTF8(STRING_ELT(json, 0));
    size_t len = strlen(text);
    decode_holder *h;
    SEXP hptr = new_holder(&h, zpb_arena_ceiling(pool, ceilings, m, (double) len, 1));
    zpb_msg *msg = h->arena != NULL ? zpb_msg_new(m, h->arena) : NULL;
    if (msg == NULL) {
        holder_finalize(hptr);
        UNPROTECT(1);
        return json_result(R_NilValue, "arena_limit", NULL);
    }
    char err[1024];
    if (!zpb_json_decode(text, len, msg, m, pool, opt_int(opts, "ignore_unknown") != 0,
                         h->arena, err, sizeof err)) {
        const char *code = h->alloc.exceeded ? "arena_limit" : "json";
        SEXP out = PROTECT(json_result(R_NilValue, code, err));
        holder_finalize(hptr);
        UNPROTECT(2);
        return out;
    }
    int status;
    size_t n = 0;
    char *bytes = zpb_encode_message(msg, m, true, opt_int(opts, "check_required") != 0,
                                     h->arena, &n, &status);
    if (bytes == NULL) {
        const char *code = status == ZPB_ENCODE_MISSING_REQUIRED ? "missing_required"
                           : status == ZPB_ENCODE_DEPTH          ? "max_depth"
                           : h->alloc.exceeded                   ? "arena_limit"
                                                                 : "out_of_memory";
        holder_finalize(hptr);
        UNPROTECT(1);
        return json_result(R_NilValue, code, NULL);
    }
    SEXP raw = PROTECT(Rf_allocVector(RAWSXP, (R_xlen_t) n));
    if (n > 0) memcpy(RAW(raw), bytes, n);
    holder_finalize(hptr);
    SEXP out = json_result(raw, NULL, NULL);
    UNPROTECT(2);
    return out;
}
