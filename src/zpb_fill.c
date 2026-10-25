#include <errno.h>
#include <math.h>
#include <stdlib.h>
#include <string.h>

#include "zpb.h"
#include "zpb_build.h"

/* proto_encode()'s C half (design section 7): walk an R value against the
 * message definition and set fields on a upb message. A value of the wrong
 * shape stops the walk with an error code, a description and the field's
 * path, which zpb_encode() returns for R to raise. No upb call that can
 * longjmp is made here. The few R objects made (length-1 vectors for a
 * ListValue's elements) are protected while used, so an R error, from
 * translating a string say, only unwinds through these frames; the arena
 * is owned by a finalised external pointer. Strings handed to upb point
 * into R memory that lives until the .Call returns. */

enum {
    FILL_OK = 0,
    FILL_TYPE,          /* zuproto_type_mismatch */
    FILL_UNKNOWN_FIELD, /* zuproto_unknown_field */
    FILL_MEMORY
};

typedef struct {
    const zpb_defpool *pool;
    zpb_arena *arena;
    int ignore_extra;
    int write_unknown;
    int err;
    const char *detail;
    char path[1024];
    size_t path_len;
} fill_ctx;

static int fill_value(fill_ctx *ctx, const zpb_msgdef *m, zpb_msg *msg, SEXP x);

/* ---- Paths: "points[2].x", "counts[\"a\"]" ---- */

static size_t path_push(fill_ctx *ctx, const char *fmt, const char *s, long n)
{
    size_t at = ctx->path_len;
    if (at < sizeof ctx->path) {
        int w = s != NULL ? snprintf(ctx->path + at, sizeof ctx->path - at, fmt, s)
                          : snprintf(ctx->path + at, sizeof ctx->path - at, fmt, n);
        if (w > 0) ctx->path_len = at + (size_t) w < sizeof ctx->path
                                       ? at + (size_t) w
                                       : sizeof ctx->path - 1;
    }
    return at;
}

static void path_pop(fill_ctx *ctx, size_t at)
{
    ctx->path_len = at;
    ctx->path[at] = '\0';
}

static size_t path_field(fill_ctx *ctx, const char *name)
{
    return path_push(ctx, ctx->path_len == 0 ? "%s" : ".%s", name, 0);
}

static int fail(fill_ctx *ctx, int err, const char *detail)
{
    ctx->err = err;
    ctx->detail = detail;
    return -1;
}

/* ---- R values ---- */

static int is_integer64(SEXP x)
{
    return TYPEOF(x) == REALSXP && Rf_inherits(x, "integer64");
}

static int64_t integer64_elt(SEXP x, R_xlen_t i)
{
    int64_t v;
    memcpy(&v, &REAL(x)[i], sizeof v);
    return v;
}

static int is_unset(SEXP x)
{
    if (x == R_NilValue) return 1;
    if (XLENGTH(x) != 1) return 0;
    if (is_integer64(x)) return integer64_elt(x, 0) == INT64_MIN; /* bit64's NA */
    switch (TYPEOF(x)) {
    case LGLSXP: return LOGICAL(x)[0] == NA_LOGICAL;
    case INTSXP: return INTEGER(x)[0] == NA_INTEGER;
    case REALSXP: return ISNA(REAL(x)[0]);
    case STRSXP: return STRING_ELT(x, 0) == NA_STRING;
    default: return 0;
    }
}

static int is_factor(SEXP x)
{
    return TYPEOF(x) == INTSXP && Rf_inherits(x, "factor");
}

static int whole_in(double d, double lo, double hi)
{
    return !ISNAN(d) && d == floor(d) && d >= lo && d <= hi;
}

/* Element i of a numeric vector as a double, or fail on NA. */
static int num_elt(fill_ctx *ctx, SEXP x, R_xlen_t i, double *out)
{
    if (TYPEOF(x) == INTSXP && !is_factor(x)) {
        if (INTEGER(x)[i] == NA_INTEGER) return fail(ctx, FILL_TYPE, "must not be NA");
        *out = INTEGER(x)[i];
        return 0;
    }
    if (is_integer64(x)) {
        int64_t v = integer64_elt(x, i);
        if (v == INT64_MIN) return fail(ctx, FILL_TYPE, "must not be NA");
        *out = (double) v;
        return 0;
    }
    if (TYPEOF(x) == REALSXP) {
        if (ISNAN(REAL(x)[i])) return fail(ctx, FILL_TYPE, "must not be NA or NaN");
        *out = REAL(x)[i];
        return 0;
    }
    return fail(ctx, FILL_TYPE, "must be numeric");
}

static int str_elt(fill_ctx *ctx, SEXP x, R_xlen_t i, const char **s)
{
    if (TYPEOF(x) != STRSXP) return fail(ctx, FILL_TYPE, "must be a character vector");
    SEXP c = STRING_ELT(x, i);
    if (c == NA_STRING) return fail(ctx, FILL_TYPE, "must not be NA");
    *s = Rf_translateCharUTF8(c);
    return 0;
}

static int parse_int64(const char *s, int64_t *out)
{
    char *end;
    errno = 0;
    long long v = strtoll(s, &end, 10);
    if (errno != 0 || end == s || *end != '\0') return -1;
    *out = (int64_t) v;
    return 0;
}

static int parse_uint64(const char *s, uint64_t *out)
{
    char *end;
    if (*s == '-' || *s == '\0') return -1;
    errno = 0;
    unsigned long long v = strtoull(s, &end, 10);
    if (errno != 0 || end == s || *end != '\0') return -1;
    *out = (uint64_t) v;
    return 0;
}

/* ---- Scalars ---- */

/* Element i of x as the value of non-message field f. */
static int scalar_elt(fill_ctx *ctx, const zpb_fielddef *f, SEXP x, R_xlen_t i,
                      zpb_value *out)
{
    memset(out, 0, sizeof *out);
    double d;
    const char *s;
    switch (zpb_field_ctype(f)) {
    case ZPB_CTYPE_BOOL:
        if (TYPEOF(x) != LGLSXP) return fail(ctx, FILL_TYPE, "must be logical");
        if (LOGICAL(x)[i] == NA_LOGICAL) return fail(ctx, FILL_TYPE, "must not be NA");
        out->bool_val = LOGICAL(x)[i] != 0;
        return 0;
    case ZPB_CTYPE_FLOAT:
        if (num_elt(ctx, x, i, &d) < 0) return -1;
        out->float_val = (float) d;
        return 0;
    case ZPB_CTYPE_DOUBLE:
        if (num_elt(ctx, x, i, &d) < 0) return -1;
        out->double_val = d;
        return 0;
    case ZPB_CTYPE_INT32:
        if (num_elt(ctx, x, i, &d) < 0) return -1;
        if (!whole_in(d, -2147483648.0, 2147483647.0))
            return fail(ctx, FILL_TYPE, "must be a whole number in the 32-bit signed range");
        out->int32_val = (int32_t) d;
        return 0;
    case ZPB_CTYPE_UINT32:
        if (num_elt(ctx, x, i, &d) < 0) return -1;
        if (!whole_in(d, 0, 4294967295.0))
            return fail(ctx, FILL_TYPE, "must be a whole number from 0 to 2^32 - 1");
        out->uint32_val = (uint32_t) d;
        return 0;
    case ZPB_CTYPE_INT64:
        if (is_integer64(x)) {
            out->int64_val = integer64_elt(x, i);
            if (out->int64_val == INT64_MIN) return fail(ctx, FILL_TYPE, "must not be NA");
            return 0;
        }
        if (TYPEOF(x) == STRSXP) {
            if (str_elt(ctx, x, i, &s) < 0) return -1;
            if (parse_int64(s, &out->int64_val) < 0)
                return fail(ctx, FILL_TYPE, "must be a decimal integer in the 64-bit signed range");
            return 0;
        }
        if (num_elt(ctx, x, i, &d) < 0) return -1;
        /* 2^63 itself is out of range; doubles below it convert exactly. */
        if (!whole_in(d, -9223372036854775808.0, 9223372036854774784.0))
            return fail(ctx, FILL_TYPE, "must be a whole number in the 64-bit signed range");
        out->int64_val = (int64_t) d;
        return 0;
    case ZPB_CTYPE_UINT64:
        if (is_integer64(x)) {
            int64_t v = integer64_elt(x, i);
            if (v == INT64_MIN) return fail(ctx, FILL_TYPE, "must not be NA");
            if (v < 0) return fail(ctx, FILL_TYPE, "must be a whole number from 0 to 2^64 - 1");
            out->uint64_val = (uint64_t) v;
            return 0;
        }
        if (TYPEOF(x) == STRSXP) {
            if (str_elt(ctx, x, i, &s) < 0) return -1;
            if (parse_uint64(s, &out->uint64_val) < 0)
                return fail(ctx, FILL_TYPE, "must be a decimal integer from 0 to 2^64 - 1");
            return 0;
        }
        if (num_elt(ctx, x, i, &d) < 0) return -1;
        if (!whole_in(d, 0, 18446744073709549568.0))
            return fail(ctx, FILL_TYPE, "must be a whole number from 0 to 2^64 - 1");
        out->uint64_val = (uint64_t) d;
        return 0;
    case ZPB_CTYPE_STRING:
        if (str_elt(ctx, x, i, &s) < 0) return -1;
        *out = zpb_value_str(s, strlen(s));
        return 0;
    case ZPB_CTYPE_ENUM: {
        const zpb_enumdef *e = zpb_field_enumdef(f);
        int32_t num;
        if (is_factor(x)) {
            int code = INTEGER(x)[i];
            if (code == NA_INTEGER) return fail(ctx, FILL_TYPE, "must not be NA");
            SEXP levels = Rf_getAttrib(x, R_LevelsSymbol);
            if (TYPEOF(levels) != STRSXP || code < 1 || code > XLENGTH(levels))
                return fail(ctx, FILL_TYPE, "is a factor with invalid codes");
            s = Rf_translateCharUTF8(STRING_ELT(levels, code - 1));
            if (!zpb_enum_number_of(e, s, strlen(s), &num))
                return fail(ctx, FILL_TYPE, "has a level that is not a value of the enum");
        } else if (TYPEOF(x) == STRSXP) {
            if (str_elt(ctx, x, i, &s) < 0) return -1;
            if (!zpb_enum_number_of(e, s, strlen(s), &num))
                return fail(ctx, FILL_TYPE, "is not the name of a value of the enum");
        } else {
            if (num_elt(ctx, x, i, &d) < 0) return -1;
            if (!whole_in(d, -2147483648.0, 2147483647.0))
                return fail(ctx, FILL_TYPE, "must be a whole number in the 32-bit signed range");
            num = (int32_t) d;
            if (!zpb_enum_accepts(e, num))
                return fail(ctx, FILL_TYPE, "is a number the closed enum does not define");
        }
        out->int32_val = num;
        return 0;
    }
    case ZPB_CTYPE_BYTES:
        /* Element i of a list of raw vectors (repeated, map values). */
        if (TYPEOF(x) != VECSXP || TYPEOF(VECTOR_ELT(x, i)) != RAWSXP)
            return fail(ctx, FILL_TYPE, "must be a list of raw vectors");
        *out = zpb_value_str((const char *) RAW(VECTOR_ELT(x, i)),
                             (size_t) XLENGTH(VECTOR_ELT(x, i)));
        return 0;
    }
    return fail(ctx, FILL_TYPE, "has a type zuproto cannot encode");
}

/* ---- Well-known types ---- */

static int is_scalar_wkt(const zpb_msgdef *m)
{
    int w = zpb_msgdef_wkt(m);
    return w == ZPB_WKT_TIMESTAMP || w == ZPB_WKT_DURATION || w == ZPB_WKT_WRAPPER;
}

static int set_field(fill_ctx *ctx, zpb_msg *msg, const zpb_fielddef *f, zpb_value v)
{
    return zpb_msg_set(msg, f, v, ctx->arena) ? 0 : fail(ctx, FILL_MEMORY, "out of memory");
}

/* Seconds as a double to (seconds, nanos), as Timestamp (nanos in
 * [0, 1e9)) or Duration (nanos with the seconds' sign) wants them. */
static int fill_seconds(fill_ctx *ctx, const zpb_msgdef *m, zpb_msg *msg, SEXP x,
                        R_xlen_t i, int timestamp)
{
    double d;
    if (num_elt(ctx, x, i, &d) < 0) return -1;
    if (!timestamp) {
        SEXP units = Rf_getAttrib(x, Rf_install("units"));
        if (TYPEOF(units) == STRSXP && XLENGTH(units) == 1) {
            const char *u = CHAR(STRING_ELT(units, 0));
            double k = strcmp(u, "secs") == 0    ? 1
                       : strcmp(u, "mins") == 0  ? 60
                       : strcmp(u, "hours") == 0 ? 3600
                       : strcmp(u, "days") == 0  ? 86400
                       : strcmp(u, "weeks") == 0 ? 604800
                                                 : 0;
            if (k == 0) return fail(ctx, FILL_TYPE, "is a difftime in units zuproto does not know");
            d *= k;
        }
    }
    if (!R_FINITE(d)) return fail(ctx, FILL_TYPE, "must be finite");
    double secs = timestamp ? floor(d) : trunc(d);
    double nanos = nearbyint((d - secs) * 1e9);
    if (fabs(nanos) >= 1e9) {
        secs += nanos > 0 ? 1 : -1;
        nanos = 0;
    }
    /* The ranges protobuf's JSON mapping allows. */
    if (timestamp ? (secs < -62135596800.0 || secs > 253402300799.0)
                  : fabs(secs) > 315576000000.0)
        return fail(ctx, FILL_TYPE, timestamp ? "is outside 0001-01-01 to 9999-12-31"
                                              : "is outside +/- 10000 years");
    zpb_value v;
    memset(&v, 0, sizeof v);
    v.int64_val = (int64_t) secs;
    if (set_field(ctx, msg, zpb_msgdef_field_by_number(m, 1), v) < 0) return -1;
    memset(&v, 0, sizeof v);
    v.int32_val = (int32_t) nanos;
    return set_field(ctx, msg, zpb_msgdef_field_by_number(m, 2), v);
}

/* Element i of x as a Timestamp, Duration or wrapper message. */
static int fill_scalar_wkt(fill_ctx *ctx, const zpb_msgdef *m, zpb_msg *msg, SEXP x,
                           R_xlen_t i)
{
    switch (zpb_msgdef_wkt(m)) {
    case ZPB_WKT_TIMESTAMP: return fill_seconds(ctx, m, msg, x, i, 1);
    case ZPB_WKT_DURATION: return fill_seconds(ctx, m, msg, x, i, 0);
    default: {
        const zpb_fielddef *vf = zpb_msgdef_field_by_number(m, 1);
        zpb_value v;
        if (zpb_field_ctype(vf) == ZPB_CTYPE_BYTES) {
            if (TYPEOF(x) == RAWSXP) {
                v = zpb_value_str((const char *) RAW(x), (size_t) XLENGTH(x));
            } else if (scalar_elt(ctx, vf, x, i, &v) < 0) {
                return -1;
            }
        } else if (scalar_elt(ctx, vf, x, i, &v) < 0) {
            return -1;
        }
        return set_field(ctx, msg, vf, v);
    }
    }
}

static int fill_struct(fill_ctx *ctx, const zpb_msgdef *m, zpb_msg *msg, SEXP x);
static int fill_list_value(fill_ctx *ctx, const zpb_msgdef *m, zpb_msg *msg, SEXP x);

/* Value: NULL or NA is null, a logical, number or string of length 1 that
 * scalar, a named list a Struct, anything else a ListValue. */
static int fill_value_wkt(fill_ctx *ctx, const zpb_msgdef *m, zpb_msg *msg, SEXP x)
{
    zpb_value v;
    memset(&v, 0, sizeof v);
    if (is_unset(x)) return set_field(ctx, msg, zpb_msgdef_field_by_number(m, 1), v);
    if (XLENGTH(x) == 1 && (!Rf_isObject(x) || is_integer64(x))) {
        switch (TYPEOF(x)) {
        case LGLSXP:
            v.bool_val = LOGICAL(x)[0] != 0;
            return set_field(ctx, msg, zpb_msgdef_field_by_number(m, 4), v);
        case INTSXP:
        case REALSXP:
            if (num_elt(ctx, x, 0, &v.double_val) < 0) return -1;
            return set_field(ctx, msg, zpb_msgdef_field_by_number(m, 2), v);
        case STRSXP: {
            const char *s = Rf_translateCharUTF8(STRING_ELT(x, 0));
            return set_field(ctx, msg, zpb_msgdef_field_by_number(m, 3),
                             zpb_value_str(s, strlen(s)));
        }
        }
    }
    const zpb_fielddef *f;
    if (TYPEOF(x) == VECSXP && Rf_getAttrib(x, R_NamesSymbol) != R_NilValue) {
        f = zpb_msgdef_field_by_number(m, 5);
        zpb_msg *sub = zpb_msg_mutable_msg(msg, f, ctx->arena);
        if (sub == NULL) return fail(ctx, FILL_MEMORY, "out of memory");
        return fill_struct(ctx, zpb_field_msgdef(f), sub, x);
    }
    f = zpb_msgdef_field_by_number(m, 6);
    zpb_msg *sub = zpb_msg_mutable_msg(msg, f, ctx->arena);
    if (sub == NULL) return fail(ctx, FILL_MEMORY, "out of memory");
    return fill_list_value(ctx, zpb_field_msgdef(f), sub, x);
}

/* Element i of an atomic vector or list, as an R value of length 1. */
static SEXP elt(SEXP x, R_xlen_t i)
{
    if (TYPEOF(x) == VECSXP) return VECTOR_ELT(x, i);
    switch (TYPEOF(x)) {
    case LGLSXP: return Rf_ScalarLogical(LOGICAL(x)[i]);
    case INTSXP: return Rf_ScalarInteger(INTEGER(x)[i]);
    case REALSXP: return Rf_ScalarReal(REAL(x)[i]);
    case STRSXP: return Rf_ScalarString(STRING_ELT(x, i));
    }
    return R_NilValue;
}

static int fill_list_value(fill_ctx *ctx, const zpb_msgdef *m, zpb_msg *msg, SEXP x)
{
    switch (TYPEOF(x)) {
    case VECSXP: case LGLSXP: case INTSXP: case REALSXP: case STRSXP: break;
    default: return fail(ctx, FILL_TYPE, "must be a list or an atomic vector");
    }
    const zpb_fielddef *values = zpb_msgdef_field_by_number(m, 1);
    const zpb_msgdef *value_def = zpb_field_msgdef(values);
    zpb_array *arr = zpb_msg_mutable_array(msg, values, ctx->arena);
    if (arr == NULL) return fail(ctx, FILL_MEMORY, "out of memory");
    for (R_xlen_t i = 0; i < XLENGTH(x); i++) {
        size_t at = path_push(ctx, "[%ld]", NULL, (long) i + 1);
        zpb_msg *sub = zpb_msg_new(value_def, ctx->arena);
        if (sub == NULL) return fail(ctx, FILL_MEMORY, "out of memory");
        /* An atomic element is a fresh length-1 vector; keep it until the
         * walk below has used it. */
        SEXP e = PROTECT(elt(x, i));
        int r = fill_value_wkt(ctx, value_def, sub, e);
        UNPROTECT(1);
        if (r < 0) return -1;
        zpb_value v;
        memset(&v, 0, sizeof v);
        v.msg_val = sub;
        if (!zpb_array_append(arr, v, ctx->arena)) return fail(ctx, FILL_MEMORY, "out of memory");
        path_pop(ctx, at);
    }
    return 0;
}

static int fill_struct(fill_ctx *ctx, const zpb_msgdef *m, zpb_msg *msg, SEXP x)
{
    SEXP names = Rf_getAttrib(x, R_NamesSymbol);
    if (TYPEOF(x) != VECSXP || (XLENGTH(x) > 0 && TYPEOF(names) != STRSXP))
        return fail(ctx, FILL_TYPE, "must be a named list");
    const zpb_fielddef *fields = zpb_msgdef_field_by_number(m, 1);
    const zpb_msgdef *entry = zpb_field_msgdef(fields);
    const zpb_msgdef *value_def = zpb_field_msgdef(zpb_msgdef_field_by_number(entry, 2));
    zpb_map *map = zpb_msg_mutable_map(msg, fields, ctx->arena);
    if (map == NULL) return fail(ctx, FILL_MEMORY, "out of memory");
    for (R_xlen_t i = 0; i < XLENGTH(x); i++) {
        if (STRING_ELT(names, i) == NA_STRING) return fail(ctx, FILL_TYPE, "must not have NA names");
        const char *key = Rf_translateCharUTF8(STRING_ELT(names, i));
        size_t at = path_push(ctx, "[\"%s\"]", key, 0);
        zpb_msg *sub = zpb_msg_new(value_def, ctx->arena);
        if (sub == NULL) return fail(ctx, FILL_MEMORY, "out of memory");
        if (fill_value_wkt(ctx, value_def, sub, VECTOR_ELT(x, i)) < 0) return -1;
        zpb_value v;
        memset(&v, 0, sizeof v);
        v.msg_val = sub;
        int r = zpb_map_insert(map, zpb_value_str(key, strlen(key)), v, ctx->arena);
        if (r == 0) return fail(ctx, FILL_MEMORY, "out of memory");
        if (r == 2) return fail(ctx, FILL_TYPE, "is a key given twice");
        path_pop(ctx, at);
    }
    return 0;
}

/* ---- Fields ---- */

/* A message-typed value: a list, or for Timestamp, Duration and wrappers an
 * R scalar (element i of x). */
static int fill_message_elt(fill_ctx *ctx, const zpb_msgdef *m, zpb_msg *sub, SEXP x,
                            R_xlen_t i)
{
    if (is_scalar_wkt(m) && TYPEOF(x) != VECSXP) return fill_scalar_wkt(ctx, m, sub, x, i);
    return fill_value(ctx, m, sub, TYPEOF(x) == VECSXP ? VECTOR_ELT(x, i) : x);
}

static int fill_repeated(fill_ctx *ctx, zpb_msg *msg, const zpb_fielddef *f, SEXP x)
{
    zpb_array *arr = zpb_msg_mutable_array(msg, f, ctx->arena);
    if (arr == NULL) return fail(ctx, FILL_MEMORY, "out of memory");
    int ct = zpb_field_ctype(f);
    const zpb_msgdef *sm = ct == ZPB_CTYPE_MESSAGE ? zpb_field_msgdef(f) : NULL;
    if (ct == ZPB_CTYPE_MESSAGE && TYPEOF(x) != VECSXP && !is_scalar_wkt(sm))
        return fail(ctx, FILL_TYPE, "must be a list of messages");
    for (R_xlen_t i = 0; i < XLENGTH(x); i++) {
        size_t at = path_push(ctx, "[%ld]", NULL, (long) i + 1);
        zpb_value v;
        if (ct == ZPB_CTYPE_MESSAGE) {
            zpb_msg *sub = zpb_msg_new(sm, ctx->arena);
            if (sub == NULL) return fail(ctx, FILL_MEMORY, "out of memory");
            if (fill_message_elt(ctx, sm, sub, x, i) < 0) return -1;
            memset(&v, 0, sizeof v);
            v.msg_val = sub;
        } else if (scalar_elt(ctx, f, x, i, &v) < 0) {
            return -1;
        }
        if (!zpb_array_append(arr, v, ctx->arena)) return fail(ctx, FILL_MEMORY, "out of memory");
        path_pop(ctx, at);
    }
    return 0;
}

static int map_key(fill_ctx *ctx, const zpb_fielddef *kf, const char *s, zpb_value *k)
{
    memset(k, 0, sizeof *k);
    switch (zpb_field_ctype(kf)) {
    case ZPB_CTYPE_STRING: *k = zpb_value_str(s, strlen(s)); return 0;
    case ZPB_CTYPE_BOOL:
        if (strcmp(s, "true") == 0) k->bool_val = 1;
        else if (strcmp(s, "false") != 0)
            return fail(ctx, FILL_TYPE, "is a bool map key that is not \"true\" or \"false\"");
        return 0;
    case ZPB_CTYPE_INT32:
    case ZPB_CTYPE_INT64: {
        int64_t v;
        int is32 = zpb_field_ctype(kf) == ZPB_CTYPE_INT32;
        if (parse_int64(s, &v) < 0 || (is32 && (v < INT32_MIN || v > INT32_MAX)))
            return fail(ctx, FILL_TYPE, "is a map key that is not a decimal integer in range");
        if (is32) k->int32_val = (int32_t) v;
        else k->int64_val = v;
        return 0;
    }
    default: {
        uint64_t v;
        int is32 = zpb_field_ctype(kf) == ZPB_CTYPE_UINT32;
        if (parse_uint64(s, &v) < 0 || (is32 && v > UINT32_MAX))
            return fail(ctx, FILL_TYPE, "is a map key that is not a decimal integer in range");
        if (is32) k->uint32_val = (uint32_t) v;
        else k->uint64_val = v;
        return 0;
    }
    }
}

static int fill_map(fill_ctx *ctx, zpb_msg *msg, const zpb_fielddef *f, SEXP x)
{
    const zpb_msgdef *entry = zpb_field_msgdef(f);
    const zpb_fielddef *kf = zpb_msgdef_field_by_number(entry, 1);
    const zpb_fielddef *vf = zpb_msgdef_field_by_number(entry, 2);
    SEXP names = Rf_getAttrib(x, R_NamesSymbol);
    if (XLENGTH(x) > 0 && TYPEOF(names) != STRSXP)
        return fail(ctx, FILL_TYPE, "must be a named vector or list, the names being the keys");
    zpb_map *map = zpb_msg_mutable_map(msg, f, ctx->arena);
    if (map == NULL) return fail(ctx, FILL_MEMORY, "out of memory");
    int ct = zpb_field_ctype(vf);
    const zpb_msgdef *sm = ct == ZPB_CTYPE_MESSAGE ? zpb_field_msgdef(vf) : NULL;
    for (R_xlen_t i = 0; i < XLENGTH(x); i++) {
        if (STRING_ELT(names, i) == NA_STRING) return fail(ctx, FILL_TYPE, "must not have NA names");
        const char *s = Rf_translateCharUTF8(STRING_ELT(names, i));
        size_t at = path_push(ctx, "[\"%s\"]", s, 0);
        zpb_value k, v;
        if (map_key(ctx, kf, s, &k) < 0) return -1;
        if (ct == ZPB_CTYPE_MESSAGE) {
            if (TYPEOF(x) != VECSXP && !is_scalar_wkt(sm))
                return fail(ctx, FILL_TYPE, "must be a named list of messages");
            zpb_msg *sub = zpb_msg_new(sm, ctx->arena);
            if (sub == NULL) return fail(ctx, FILL_MEMORY, "out of memory");
            if (fill_message_elt(ctx, sm, sub, x, i) < 0) return -1;
            memset(&v, 0, sizeof v);
            v.msg_val = sub;
        } else if (scalar_elt(ctx, vf, x, i, &v) < 0) {
            return -1;
        }
        int r = zpb_map_insert(map, k, v, ctx->arena);
        if (r == 0) return fail(ctx, FILL_MEMORY, "out of memory");
        if (r == 2) return fail(ctx, FILL_TYPE, "is a key given twice");
        path_pop(ctx, at);
    }
    return 0;
}

static int fill_field(fill_ctx *ctx, zpb_msg *msg, const zpb_fielddef *f, SEXP x)
{
    if (zpb_field_is_map(f)) return fill_map(ctx, msg, f, x);
    if (zpb_field_is_repeated(f)) {
        if (TYPEOF(x) != VECSXP && !Rf_isVectorAtomic(x))
            return fail(ctx, FILL_TYPE, "must be a vector or a list");
        return fill_repeated(ctx, msg, f, x);
    }
    int ct = zpb_field_ctype(f);
    if (ct == ZPB_CTYPE_MESSAGE) {
        const zpb_msgdef *sm = zpb_field_msgdef(f);
        zpb_msg *sub = zpb_msg_mutable_msg(msg, f, ctx->arena);
        if (sub == NULL) return fail(ctx, FILL_MEMORY, "out of memory");
        if (is_scalar_wkt(sm) && TYPEOF(x) != VECSXP) {
            /* A BytesValue's value is a whole raw vector. */
            if (XLENGTH(x) != 1 && TYPEOF(x) != RAWSXP)
                return fail(ctx, FILL_TYPE, "must have length 1");
            return fill_scalar_wkt(ctx, sm, sub, x, 0);
        }
        return fill_value(ctx, sm, sub, x);
    }
    zpb_value v;
    if (ct == ZPB_CTYPE_BYTES) {
        if (TYPEOF(x) != RAWSXP) return fail(ctx, FILL_TYPE, "must be a raw vector");
        v = zpb_value_str((const char *) RAW(x), (size_t) XLENGTH(x));
    } else {
        if (XLENGTH(x) != 1) return fail(ctx, FILL_TYPE, "must have length 1");
        if (scalar_elt(ctx, f, x, 0, &v) < 0) return -1;
    }
    return set_field(ctx, msg, f, v);
}

/* ---- Messages ---- */

static int fill_generic(fill_ctx *ctx, const zpb_msgdef *m, zpb_msg *msg, SEXP x)
{
    if (TYPEOF(x) != VECSXP) return fail(ctx, FILL_TYPE, "must be a list");
    SEXP names = Rf_getAttrib(x, R_NamesSymbol);
    R_xlen_t n = XLENGTH(x);
    if (n > 0 && TYPEOF(names) != STRSXP) return fail(ctx, FILL_TYPE, "must be a named list");

    /* Oneofs given a member so far, to refuse a second. */
    const void **oneofs = n > 0 ? (const void **) R_alloc((size_t) n, sizeof *oneofs) : NULL;
    R_xlen_t n_oneofs = 0;

    for (R_xlen_t i = 0; i < n; i++) {
        SEXP v = VECTOR_ELT(x, i);
        if (STRING_ELT(names, i) == NA_STRING) return fail(ctx, FILL_TYPE, "must not have NA names");
        const char *name = Rf_translateCharUTF8(STRING_ELT(names, i));
        size_t len = strlen(name);
        size_t at = path_field(ctx, name);

        const zpb_fielddef *f;
        if (len > 2 && name[0] == '[' && name[len - 1] == ']') {
            char *ext = R_alloc(len - 1, 1);
            memcpy(ext, name + 1, len - 2);
            ext[len - 2] = '\0';
            f = zpb_find_extension(ctx->pool, m, ext);
        } else {
            f = zpb_msgdef_find_field(m, name, len);
        }
        if (f == NULL) {
            if (ctx->ignore_extra) {
                path_pop(ctx, at);
                continue;
            }
            return fail(ctx, FILL_UNKNOWN_FIELD, "is not a field of the message type");
        }

        /* NULL and NA mean unset; so does an empty value of a singular field. */
        if (zpb_field_is_repeated(f) ? v == R_NilValue : is_unset(v)) {
            path_pop(ctx, at);
            continue;
        }
        const void *oneof = zpb_field_oneof_def(f);
        if (oneof != NULL) {
            for (R_xlen_t j = 0; j < n_oneofs; j++)
                if (oneofs[j] == oneof)
                    return fail(ctx, FILL_TYPE, "is a second member of a oneof given a value");
            oneofs[n_oneofs++] = oneof;
        }
        if (fill_field(ctx, msg, f, v) < 0) return -1;
        path_pop(ctx, at);
    }

    if (ctx->write_unknown) {
        SEXP unknown = Rf_getAttrib(x, Rf_install("proto_unknown"));
        if (TYPEOF(unknown) == RAWSXP && XLENGTH(unknown) > 0 &&
            !zpb_msg_add_unknown(msg, (const char *) RAW(unknown), (size_t) XLENGTH(unknown),
                                 ctx->arena))
            return fail(ctx, FILL_MEMORY, "out of memory");
    }
    return 0;
}

static int fill_value(fill_ctx *ctx, const zpb_msgdef *m, zpb_msg *msg, SEXP x)
{
    R_CheckStack();
    switch (zpb_msgdef_wkt(m)) {
    case ZPB_WKT_TIMESTAMP:
    case ZPB_WKT_DURATION:
    case ZPB_WKT_WRAPPER:
        if (TYPEOF(x) == VECSXP) break; /* given as fields, a list */
        if (XLENGTH(x) != 1 && TYPEOF(x) != RAWSXP) return fail(ctx, FILL_TYPE, "must have length 1");
        return fill_scalar_wkt(ctx, m, msg, x, 0);
    case ZPB_WKT_STRUCT: return fill_struct(ctx, m, msg, x);
    case ZPB_WKT_LISTVALUE: return fill_list_value(ctx, m, msg, x);
    case ZPB_WKT_VALUE: return fill_value_wkt(ctx, m, msg, x);
    case ZPB_WKT_FIELDMASK:
        if (TYPEOF(x) == STRSXP) return fill_repeated(ctx, msg, zpb_msgdef_field_by_number(m, 1), x);
        break;
    case ZPB_WKT_ANY:
        if (TYPEOF(x) == VECSXP && XLENGTH(x) == 2) break; /* list(type_url, value) */
        return fail(ctx, FILL_TYPE, "must be list(type_url = <string>, value = <raw>)");
    }
    return fill_generic(ctx, m, msg, x);
}

/* ---- Entry point ---- */

static void arena_finalize(SEXP ptr)
{
    zpb_arena *a = (zpb_arena *) R_ExternalPtrAddr(ptr);
    if (a != NULL) {
        zpb_arena_free(a);
        R_ClearExternalPtr(ptr);
    }
}

static SEXP result(SEXP value, const char *error, const char *path, const char *detail)
{
    const char *names[] = {"value", "error", "path", "detail", ""};
    PROTECT(value);
    SEXP out = PROTECT(Rf_mkNamed(VECSXP, names));
    SET_VECTOR_ELT(out, 0, value);
    SET_VECTOR_ELT(out, 1, error ? Rf_mkString(error) : R_NilValue);
    SET_VECTOR_ELT(out, 2, path ? Rf_mkString(path) : R_NilValue);
    SET_VECTOR_ELT(out, 3, detail ? Rf_mkString(detail) : R_NilValue);
    UNPROTECT(2);
    return out;
}

/* Encode R value x as message type `type` of pool. Returns list(value,
 * error, path, detail): value the raw bytes, or error one of
 * "unknown_type", "type_mismatch", "unknown_field", "missing_required",
 * "out_of_memory", "other". opts: deterministic, check_required,
 * write_unknown, ignore_extra (integers). */
SEXP zpb_encode(SEXP ptr, SEXP type, SEXP x, SEXP opts)
{
    const zpb_defpool *pool = zpb_pool_get(ptr);
    const zpb_msgdef *m =
        zpb_defpool_find_message(pool, Rf_translateCharUTF8(STRING_ELT(type, 0)));
    if (m == NULL) return result(R_NilValue, "unknown_type", NULL, NULL);

    zpb_arena *a = zpb_arena_new();
    if (a == NULL) Rf_error("zuproto: out of memory creating an arena");
    SEXP aptr = PROTECT(R_MakeExternalPtr(a, R_NilValue, R_NilValue));
    R_RegisterCFinalizerEx(aptr, arena_finalize, TRUE);

    fill_ctx ctx;
    memset(&ctx, 0, sizeof ctx);
    ctx.pool = pool;
    ctx.arena = a;
    ctx.write_unknown = INTEGER(VECTOR_ELT(opts, 2))[0];
    ctx.ignore_extra = INTEGER(VECTOR_ELT(opts, 3))[0];

    zpb_msg *msg = zpb_msg_new(m, a);
    if (msg == NULL) {
        arena_finalize(aptr);
        UNPROTECT(1);
        return result(R_NilValue, "out_of_memory", NULL, NULL);
    }
    if (fill_value(&ctx, m, msg, x) < 0) {
        const char *err = ctx.err == FILL_TYPE            ? "type_mismatch"
                          : ctx.err == FILL_UNKNOWN_FIELD ? "unknown_field"
                                                          : "out_of_memory";
        SEXP out = PROTECT(result(R_NilValue, err, ctx.path, ctx.detail));
        arena_finalize(aptr);
        UNPROTECT(2);
        return out;
    }

    int status;
    size_t len = 0;
    char *buf = zpb_encode_message(msg, m, INTEGER(VECTOR_ELT(opts, 0))[0] != 0,
                                   INTEGER(VECTOR_ELT(opts, 1))[0] != 0, a, &len, &status);
    if (buf == NULL) {
        arena_finalize(aptr);
        UNPROTECT(1);
        return result(R_NilValue,
                      status == ZPB_ENCODE_MISSING_REQUIRED ? "missing_required"
                      : status == ZPB_ENCODE_MEMORY        ? "out_of_memory"
                                                           : "other",
                      NULL, NULL);
    }
    SEXP raw = PROTECT(Rf_allocVector(RAWSXP, (R_xlen_t) len));
    if (len > 0) memcpy(RAW(raw), buf, len);
    arena_finalize(aptr);
    SEXP out = result(raw, NULL, NULL, NULL);
    UNPROTECT(2);
    return out;
}
