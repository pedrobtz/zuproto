#include <math.h>
#include <stdlib.h>
#include <string.h>

#include "zpb.h"
#include "zpb_build.h"

/* Building R values from a decoded message (design sections 6.1 to 6.3).
 * Only ever called after the decode succeeded, so no upb error can
 * longjmp through here. A value R cannot hold records an error in the
 * context, and every function then returns NULL with its PROTECTs undone,
 * so the entry point can return the error to R to raise. */

#define TWO_53_INT ((uint64_t) 1 << 53)

static SEXP build_message(zpb_build_ctx *ctx, const zpb_msgdef *m,
                          const zpb_msg *msg);

static int fail(zpb_build_ctx *ctx, int err, const zpb_fielddef *f)
{
    ctx->err = err;
    ctx->err_field = f != NULL ? zpb_field_full_name(f) : NULL;
    return -1;
}

/* ---- Strings and bytes ---- */

static SEXP mk_utf8(zpb_build_ctx *ctx, zpb_str s, const zpb_fielddef *f)
{
    if (s.size > 0 && memchr(s.data, '\0', s.size) != NULL) {
        fail(ctx, ZPB_BUILD_ERR_NUL, f);
        return NULL;
    }
    if (s.size > INT_MAX) {
        fail(ctx, ZPB_BUILD_ERR_LONG_STRING, f);
        return NULL;
    }
    return Rf_mkCharLenCE(s.data, (int) s.size, CE_UTF8);
}

static const char b64_digits[] =
    "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

/* Standard base64 with padding, as protobuf JSON writes bytes. */
static SEXP mk_base64(zpb_build_ctx *ctx, zpb_str s, const zpb_fielddef *f)
{
    if (s.size > ((size_t) INT_MAX / 4) * 3) {
        fail(ctx, ZPB_BUILD_ERR_LONG_STRING, f);
        return NULL;
    }
    size_t out_len = 4 * ((s.size + 2) / 3);
    char *out = R_alloc(out_len + 1, 1);
    const unsigned char *in = (const unsigned char *) s.data;
    size_t j = 0;
    for (size_t i = 0; i < s.size; i += 3) {
        unsigned v = (unsigned) in[i] << 16;
        if (i + 1 < s.size) v |= (unsigned) in[i + 1] << 8;
        if (i + 2 < s.size) v |= in[i + 2];
        out[j++] = b64_digits[(v >> 18) & 63];
        out[j++] = b64_digits[(v >> 12) & 63];
        out[j++] = i + 1 < s.size ? b64_digits[(v >> 6) & 63] : '=';
        out[j++] = i + 2 < s.size ? b64_digits[v & 63] : '=';
    }
    return Rf_mkCharLenCE(out, (int) out_len, CE_UTF8);
}

static SEXP mk_raw(zpb_str s)
{
    SEXP out = Rf_allocVector(RAWSXP, (R_xlen_t) s.size);
    if (s.size > 0) memcpy(RAW(out), s.data, s.size);
    return out;
}

/* ---- Enums ---- */

/* The levels of an enum's factor: its value names, in definition order,
 * each once (aliases share a number; the first name wins on decode). */
static SEXP enum_levels(const zpb_enumdef *e)
{
    int n = zpb_enum_value_count(e);
    SEXP levels = PROTECT(Rf_allocVector(STRSXP, n));
    for (int i = 0; i < n; i++)
        SET_STRING_ELT(levels, i, Rf_mkCharCE(zpb_enum_value_name(e, i), CE_UTF8));
    UNPROTECT(1);
    return levels;
}

/* 1-based level of number v, or NA_INTEGER for a number the enum lacks. */
static int enum_code(const zpb_enumdef *e, int32_t v)
{
    const char *name = zpb_enum_name_of(e, v);
    if (name == NULL) return NA_INTEGER;
    int n = zpb_enum_value_count(e);
    for (int i = 0; i < n; i++)
        if (strcmp(zpb_enum_value_name(e, i), name) == 0) return i + 1;
    return NA_INTEGER;
}

/* ---- Values of one field ---- */

static const zpb_fielddef *wrapper_value_field(const zpb_msgdef *m)
{
    return zpb_msgdef_field_by_number(m, 1);
}

/* The R type a field's values take, for n of them. */
static SEXP alloc_values(zpb_build_ctx *ctx, const zpb_fielddef *f, R_xlen_t n)
{
    switch (zpb_field_ctype(f)) {
    case ZPB_CTYPE_BOOL: return Rf_allocVector(LGLSXP, n);
    case ZPB_CTYPE_FLOAT:
    case ZPB_CTYPE_DOUBLE:
    case ZPB_CTYPE_UINT32: return Rf_allocVector(REALSXP, n);
    case ZPB_CTYPE_INT32: return Rf_allocVector(INTSXP, n);
    case ZPB_CTYPE_INT64:
    case ZPB_CTYPE_UINT64:
        return Rf_allocVector(ctx->int64 == ZPB_INT64_CHARACTER ? STRSXP : REALSXP, n);
    case ZPB_CTYPE_ENUM:
        return Rf_allocVector(ctx->enums == ZPB_ENUMS_CHARACTER ? STRSXP : INTSXP, n);
    case ZPB_CTYPE_STRING: return Rf_allocVector(STRSXP, n);
    case ZPB_CTYPE_BYTES:
        return Rf_allocVector(ctx->bytes_base64 ? STRSXP : VECSXP, n);
    case ZPB_CTYPE_MESSAGE: {
        const zpb_msgdef *m = zpb_field_msgdef(f);
        int w = zpb_msgdef_wkt(m);
        if (w == ZPB_WKT_TIMESTAMP || w == ZPB_WKT_DURATION)
            return Rf_allocVector(REALSXP, n);
        if (w == ZPB_WKT_WRAPPER) return alloc_values(ctx, wrapper_value_field(m), n);
        return Rf_allocVector(VECSXP, n);
    }
    }
    return Rf_allocVector(VECSXP, n);
}

static double seconds_nanos(const zpb_msg *msg, const zpb_msgdef *m)
{
    int64_t s = zpb_msg_get(msg, zpb_msgdef_field_by_number(m, 1)).int64_val;
    int32_t ns = zpb_msg_get(msg, zpb_msgdef_field_by_number(m, 2)).int32_val;
    /* Sub-microsecond digits are rounded (design section 6.3). */
    return (double) s + nearbyint((double) ns / 1000.0) / 1e6;
}

/* Write value v of field f at position i of out (from alloc_values). */
static int set_value(zpb_build_ctx *ctx, const zpb_fielddef *f, SEXP out,
                     R_xlen_t i, zpb_value v)
{
    switch (zpb_field_ctype(f)) {
    case ZPB_CTYPE_BOOL: LOGICAL(out)[i] = v.bool_val; return 0;
    case ZPB_CTYPE_FLOAT: REAL(out)[i] = (double) v.float_val; return 0;
    case ZPB_CTYPE_DOUBLE: REAL(out)[i] = v.double_val; return 0;
    case ZPB_CTYPE_UINT32: REAL(out)[i] = (double) v.uint32_val; return 0;
    case ZPB_CTYPE_INT32:
        if (v.int32_val == INT_MIN) ctx->precision_loss++;
        INTEGER(out)[i] = v.int32_val == INT_MIN ? NA_INTEGER : v.int32_val;
        return 0;
    case ZPB_CTYPE_INT64:
    case ZPB_CTYPE_UINT64: {
        int is_signed = zpb_field_ctype(f) == ZPB_CTYPE_INT64;
        if (ctx->int64 == ZPB_INT64_CHARACTER) {
            char buf[32];
            if (is_signed)
                snprintf(buf, sizeof buf, "%lld", (long long) v.int64_val);
            else
                snprintf(buf, sizeof buf, "%llu", (unsigned long long) v.uint64_val);
            SET_STRING_ELT(out, i, Rf_mkChar(buf));
        } else {
            /* Judge exactness on the integer: past 2^53 a double cannot
             * tell a rounded value from an exact one. */
            int exact = is_signed ? (v.int64_val >= -(int64_t) TWO_53_INT &&
                                     v.int64_val <= (int64_t) TWO_53_INT) ||
                                        (int64_t) (double) v.int64_val == v.int64_val
                                  : v.uint64_val <= TWO_53_INT ||
                                        (uint64_t) (double) v.uint64_val == v.uint64_val;
            if (!exact) ctx->precision_loss++;
            REAL(out)[i] = is_signed ? (double) v.int64_val : (double) v.uint64_val;
        }
        return 0;
    }
    case ZPB_CTYPE_ENUM: {
        const zpb_enumdef *e = zpb_field_enumdef(f);
        if (ctx->enums == ZPB_ENUMS_INTEGER) {
            if (v.int32_val == INT_MIN) ctx->precision_loss++;
            INTEGER(out)[i] = v.int32_val == INT_MIN ? NA_INTEGER : v.int32_val;
        } else if (ctx->enums == ZPB_ENUMS_CHARACTER) {
            const char *name = zpb_enum_name_of(e, v.int32_val);
            if (name == NULL) ctx->unknown_enum++;
            SET_STRING_ELT(out, i, name ? Rf_mkCharCE(name, CE_UTF8) : NA_STRING);
        } else {
            int code = enum_code(e, v.int32_val);
            if (code == NA_INTEGER) ctx->unknown_enum++;
            INTEGER(out)[i] = code;
        }
        return 0;
    }
    case ZPB_CTYPE_STRING: {
        SEXP s = mk_utf8(ctx, zpb_str_from(v.str_val), f);
        if (s == NULL) return -1;
        SET_STRING_ELT(out, i, s);
        return 0;
    }
    case ZPB_CTYPE_BYTES:
        if (ctx->bytes_base64) {
            SEXP s = mk_base64(ctx, zpb_str_from(v.str_val), f);
            if (s == NULL) return -1;
            SET_STRING_ELT(out, i, s);
        } else {
            SET_VECTOR_ELT(out, i, mk_raw(zpb_str_from(v.str_val)));
        }
        return 0;
    case ZPB_CTYPE_MESSAGE: {
        const zpb_msgdef *m = zpb_field_msgdef(f);
        int w = zpb_msgdef_wkt(m);
        if (w == ZPB_WKT_TIMESTAMP || w == ZPB_WKT_DURATION) {
            REAL(out)[i] = seconds_nanos(v.msg_val, m);
            return 0;
        }
        if (w == ZPB_WKT_WRAPPER) {
            const zpb_fielddef *vf = wrapper_value_field(m);
            return set_value(ctx, vf, out, i, zpb_msg_get(v.msg_val, vf));
        }
        SEXP x = build_message(ctx, m, v.msg_val);
        if (x == NULL) return -1;
        SET_VECTOR_ELT(out, i, x);
        return 0;
    }
    }
    return 0;
}

/* Attributes a field's values need once filled: factor levels, POSIXct,
 * difftime. */
static void finish_values(zpb_build_ctx *ctx, const zpb_fielddef *f, SEXP out)
{
    int ct = zpb_field_ctype(f);
    if (ct == ZPB_CTYPE_ENUM && ctx->enums == ZPB_ENUMS_FACTOR) {
        Rf_setAttrib(out, R_LevelsSymbol, enum_levels(zpb_field_enumdef(f)));
        Rf_setAttrib(out, R_ClassSymbol, Rf_mkString("factor"));
    } else if (ct == ZPB_CTYPE_MESSAGE) {
        const zpb_msgdef *m = zpb_field_msgdef(f);
        int w = zpb_msgdef_wkt(m);
        if (w == ZPB_WKT_TIMESTAMP) {
            SEXP cls = PROTECT(Rf_allocVector(STRSXP, 2));
            SET_STRING_ELT(cls, 0, Rf_mkChar("POSIXct"));
            SET_STRING_ELT(cls, 1, Rf_mkChar("POSIXt"));
            Rf_setAttrib(out, R_ClassSymbol, cls);
            Rf_setAttrib(out, Rf_install("tzone"), Rf_mkString("UTC"));
            UNPROTECT(1);
        } else if (w == ZPB_WKT_DURATION) {
            Rf_setAttrib(out, Rf_install("units"), Rf_mkString("secs"));
            Rf_setAttrib(out, R_ClassSymbol, Rf_mkString("difftime"));
        } else if (w == ZPB_WKT_WRAPPER) {
            finish_values(ctx, wrapper_value_field(m), out);
        }
    }
}

/* One value of a singular field. */
static SEXP build_single(zpb_build_ctx *ctx, const zpb_fielddef *f, zpb_value v)
{
    SEXP out = PROTECT(alloc_values(ctx, f, 1));
    if (set_value(ctx, f, out, 0, v) < 0) {
        UNPROTECT(1);
        return NULL;
    }
    finish_values(ctx, f, out);
    /* A single bytes or message value is the element, not a list of one,
     * unless it became an R scalar (well-known types, base64). */
    if (TYPEOF(out) == VECSXP) {
        SEXP elt = VECTOR_ELT(out, 0);
        UNPROTECT(1);
        return elt;
    }
    UNPROTECT(1);
    return out;
}

static SEXP build_array(zpb_build_ctx *ctx, const zpb_fielddef *f,
                        const zpb_array *a)
{
    size_t n = zpb_array_size(a);
    SEXP out = PROTECT(alloc_values(ctx, f, (R_xlen_t) n));
    for (size_t i = 0; i < n; i++) {
        if (set_value(ctx, f, out, (R_xlen_t) i, zpb_array_get(a, i)) < 0) {
            UNPROTECT(1);
            return NULL;
        }
    }
    finish_values(ctx, f, out);
    UNPROTECT(1);
    return out;
}

/* ---- Maps: entries sorted by key ---- */

typedef struct {
    zpb_value key;
    zpb_value val;
} map_entry;

static int map_key_ctype;

static int cmp_entry(const void *a, const void *b)
{
    const zpb_value *x = &((const map_entry *) a)->key;
    const zpb_value *y = &((const map_entry *) b)->key;
    switch (map_key_ctype) {
    case ZPB_CTYPE_BOOL: return (int) x->bool_val - (int) y->bool_val;
    case ZPB_CTYPE_INT32:
        return (x->int32_val > y->int32_val) - (x->int32_val < y->int32_val);
    case ZPB_CTYPE_UINT32:
        return (x->uint32_val > y->uint32_val) - (x->uint32_val < y->uint32_val);
    case ZPB_CTYPE_INT64:
        return (x->int64_val > y->int64_val) - (x->int64_val < y->int64_val);
    case ZPB_CTYPE_UINT64:
        return (x->uint64_val > y->uint64_val) - (x->uint64_val < y->uint64_val);
    default: {
        size_t n = x->str_val.size < y->str_val.size ? x->str_val.size : y->str_val.size;
        int c = n > 0 ? memcmp(x->str_val.data, y->str_val.data, n) : 0;
        if (c != 0) return c;
        return (x->str_val.size > y->str_val.size) - (x->str_val.size < y->str_val.size);
    }
    }
}

static SEXP map_key_name(zpb_build_ctx *ctx, const zpb_fielddef *kf, zpb_value k)
{
    char buf[32];
    switch (zpb_field_ctype(kf)) {
    case ZPB_CTYPE_BOOL: return Rf_mkChar(k.bool_val ? "true" : "false");
    case ZPB_CTYPE_INT32: snprintf(buf, sizeof buf, "%d", (int) k.int32_val); break;
    case ZPB_CTYPE_UINT32: snprintf(buf, sizeof buf, "%u", (unsigned) k.uint32_val); break;
    case ZPB_CTYPE_INT64: snprintf(buf, sizeof buf, "%lld", (long long) k.int64_val); break;
    case ZPB_CTYPE_UINT64:
        snprintf(buf, sizeof buf, "%llu", (unsigned long long) k.uint64_val);
        break;
    default: return mk_utf8(ctx, zpb_str_from(k.str_val), kf);
    }
    return Rf_mkChar(buf);
}

static SEXP build_map(zpb_build_ctx *ctx, const zpb_fielddef *f, const zpb_map *map)
{
    const zpb_msgdef *entry = zpb_field_msgdef(f);
    const zpb_fielddef *kf = zpb_msgdef_field_by_number(entry, 1);
    const zpb_fielddef *vf = zpb_msgdef_field_by_number(entry, 2);
    size_t n = zpb_map_size(map);

    map_entry *entries = n > 0 ? (map_entry *) R_alloc(n, sizeof *entries) : NULL;
    size_t iter = ZPB_MAP_ITER_BEGIN, k = 0;
    zpb_value key, val;
    while (k < n && zpb_map_next(map, &key, &val, &iter)) {
        entries[k].key = key;
        entries[k].val = val;
        k++;
    }
    n = k;
    map_key_ctype = zpb_field_ctype(kf);
    if (n > 1) qsort(entries, n, sizeof *entries, cmp_entry);

    SEXP out = PROTECT(alloc_values(ctx, vf, (R_xlen_t) n));
    SEXP names = PROTECT(Rf_allocVector(STRSXP, (R_xlen_t) n));
    for (size_t i = 0; i < n; i++) {
        /* Store the key's name before building the value: the name is
         * unprotected until it is in `names`, and the value allocates. */
        SEXP nm = map_key_name(ctx, kf, entries[i].key);
        if (nm == NULL) {
            UNPROTECT(2);
            return NULL;
        }
        SET_STRING_ELT(names, (R_xlen_t) i, nm);
        if (set_value(ctx, vf, out, (R_xlen_t) i, entries[i].val) < 0) {
            UNPROTECT(2);
            return NULL;
        }
    }
    finish_values(ctx, vf, out);
    Rf_setAttrib(out, R_NamesSymbol, names);
    UNPROTECT(2);
    return out;
}

/* ---- Well-known types with their own R form ---- */

static SEXP build_value_msg(zpb_build_ctx *ctx, const zpb_msgdef *m,
                            const zpb_msg *msg);

/* Struct: a named list, keys sorted. */
static SEXP build_struct(zpb_build_ctx *ctx, const zpb_msgdef *m, const zpb_msg *msg)
{
    const zpb_fielddef *fields = zpb_msgdef_field_by_number(m, 1);
    const zpb_msgdef *entry = zpb_field_msgdef(fields);
    const zpb_fielddef *vf = zpb_msgdef_field_by_number(entry, 2);
    const zpb_msgdef *value_def = zpb_field_msgdef(vf);
    const zpb_map *map = zpb_msg_get(msg, fields).map_val;
    size_t n = zpb_map_size(map);

    map_entry *entries = n > 0 ? (map_entry *) R_alloc(n, sizeof *entries) : NULL;
    size_t iter = ZPB_MAP_ITER_BEGIN, k = 0;
    zpb_value key, val;
    while (k < n && zpb_map_next(map, &key, &val, &iter)) {
        entries[k].key = key;
        entries[k].val = val;
        k++;
    }
    n = k;
    map_key_ctype = ZPB_CTYPE_STRING;
    if (n > 1) qsort(entries, n, sizeof *entries, cmp_entry);

    SEXP out = PROTECT(Rf_allocVector(VECSXP, (R_xlen_t) n));
    SEXP names = PROTECT(Rf_allocVector(STRSXP, (R_xlen_t) n));
    for (size_t i = 0; i < n; i++) {
        SEXP nm = mk_utf8(ctx, zpb_str_from(entries[i].key.str_val), fields);
        if (nm == NULL) {
            UNPROTECT(2);
            return NULL;
        }
        SET_STRING_ELT(names, (R_xlen_t) i, nm);
        SEXP x = build_value_msg(ctx, value_def, entries[i].val.msg_val);
        if (x == NULL) {
            UNPROTECT(2);
            return NULL;
        }
        SET_VECTOR_ELT(out, (R_xlen_t) i, x);
    }
    Rf_setAttrib(out, R_NamesSymbol, names);
    UNPROTECT(2);
    return out;
}

/* ListValue: a list. */
static SEXP build_list_value(zpb_build_ctx *ctx, const zpb_msgdef *m, const zpb_msg *msg)
{
    const zpb_fielddef *values = zpb_msgdef_field_by_number(m, 1);
    const zpb_msgdef *value_def = zpb_field_msgdef(values);
    const zpb_array *a = zpb_msg_get(msg, values).array_val;
    size_t n = zpb_array_size(a);
    SEXP out = PROTECT(Rf_allocVector(VECSXP, (R_xlen_t) n));
    for (size_t i = 0; i < n; i++) {
        SEXP x = build_value_msg(ctx, value_def, zpb_array_get(a, i).msg_val);
        if (x == NULL) {
            UNPROTECT(1);
            return NULL;
        }
        SET_VECTOR_ELT(out, (R_xlen_t) i, x);
    }
    UNPROTECT(1);
    return out;
}

/* Value: NULL, a number, a string, a logical, a named list or a list, as
 * protobuf JSON would have it. An unset kind is NULL too. */
static SEXP build_value_msg(zpb_build_ctx *ctx, const zpb_msgdef *m, const zpb_msg *msg)
{
    /* Struct, Value and ListValue recurse through here, not through
     * build_message(). */
    R_CheckStack();
    for (uint32_t n = 1; n <= 6; n++) {
        const zpb_fielddef *f = zpb_msgdef_field_by_number(m, n);
        if (f == NULL || !zpb_msg_has(msg, f)) continue;
        zpb_value v = zpb_msg_get(msg, f);
        switch (n) {
        case 1: return R_NilValue;
        case 2: return Rf_ScalarReal(v.double_val);
        case 3: {
            SEXP s = mk_utf8(ctx, zpb_str_from(v.str_val), f);
            return s == NULL ? NULL : Rf_ScalarString(s);
        }
        case 4: return Rf_ScalarLogical(v.bool_val);
        case 5: return build_struct(ctx, zpb_field_msgdef(f), v.msg_val);
        case 6: return build_list_value(ctx, zpb_field_msgdef(f), v.msg_val);
        }
    }
    return R_NilValue;
}

/* Any: list(type_url, value), the packed bytes left as they are. */
static SEXP build_any(zpb_build_ctx *ctx, const zpb_msgdef *m, const zpb_msg *msg)
{
    const zpb_fielddef *url = zpb_msgdef_field_by_number(m, 1);
    const zpb_fielddef *value = zpb_msgdef_field_by_number(m, 2);
    const char *names[] = {"type_url", "value", ""};
    SEXP out = PROTECT(Rf_mkNamed(VECSXP, names));
    SEXP s = mk_utf8(ctx, zpb_str_from(zpb_msg_get(msg, url).str_val), url);
    if (s == NULL) {
        UNPROTECT(1);
        return NULL;
    }
    SET_VECTOR_ELT(out, 0, Rf_ScalarString(s));
    SET_VECTOR_ELT(out, 1, mk_raw(zpb_str_from(zpb_msg_get(msg, value).str_val)));
    UNPROTECT(1);
    return out;
}

/* ---- Messages ---- */

static SEXP build_field(zpb_build_ctx *ctx, const zpb_fielddef *f, zpb_value v)
{
    if (zpb_field_is_map(f)) return build_map(ctx, f, v.map_val);
    if (zpb_field_is_repeated(f)) return build_array(ctx, f, v.array_val);
    return build_single(ctx, f, v);
}

/* Whether a field without presence holds its default (design section 5,
 * `defaults`). */
static int is_default(const zpb_fielddef *f, zpb_value v)
{
    switch (zpb_field_ctype(f)) {
    case ZPB_CTYPE_BOOL: return !v.bool_val;
    case ZPB_CTYPE_FLOAT: return v.float_val == 0 && !signbit(v.float_val);
    case ZPB_CTYPE_DOUBLE: return v.double_val == 0 && !signbit(v.double_val);
    case ZPB_CTYPE_INT32:
    case ZPB_CTYPE_ENUM: return v.int32_val == 0;
    case ZPB_CTYPE_UINT32: return v.uint32_val == 0;
    case ZPB_CTYPE_INT64: return v.int64_val == 0;
    case ZPB_CTYPE_UINT64: return v.uint64_val == 0;
    case ZPB_CTYPE_STRING:
    case ZPB_CTYPE_BYTES: return v.str_val.size == 0;
    }
    return 0;
}

static SEXP unknown_bytes(const zpb_msg *msg)
{
    uintptr_t iter = ZPB_UNKNOWN_ITER_BEGIN;
    zpb_str chunk;
    size_t total = 0;
    while (zpb_msg_next_unknown(msg, &chunk, &iter)) total += chunk.size;
    if (total == 0) return R_NilValue;
    SEXP out = Rf_allocVector(RAWSXP, (R_xlen_t) total);
    iter = ZPB_UNKNOWN_ITER_BEGIN;
    size_t at = 0;
    while (zpb_msg_next_unknown(msg, &chunk, &iter)) {
        if (chunk.size > 0) memcpy(RAW(out) + at, chunk.data, chunk.size);
        at += chunk.size;
    }
    return out;
}

static SEXP build_message(zpb_build_ctx *ctx, const zpb_msgdef *m, const zpb_msg *msg)
{
    R_CheckStack();
    switch (zpb_msgdef_wkt(m)) {
    case ZPB_WKT_TIMESTAMP:
    case ZPB_WKT_DURATION:
    case ZPB_WKT_WRAPPER: {
        /* A message decoded as one of these types itself, rather than as a
         * field's value: the same R scalar a field would give. */
        if (zpb_msgdef_wkt(m) == ZPB_WKT_WRAPPER) {
            const zpb_fielddef *vf = wrapper_value_field(m);
            return build_single(ctx, vf, zpb_msg_get(msg, vf));
        }
        SEXP out = PROTECT(Rf_ScalarReal(seconds_nanos(msg, m)));
        if (zpb_msgdef_wkt(m) == ZPB_WKT_TIMESTAMP) {
            SEXP cls = PROTECT(Rf_allocVector(STRSXP, 2));
            SET_STRING_ELT(cls, 0, Rf_mkChar("POSIXct"));
            SET_STRING_ELT(cls, 1, Rf_mkChar("POSIXt"));
            Rf_setAttrib(out, R_ClassSymbol, cls);
            Rf_setAttrib(out, Rf_install("tzone"), Rf_mkString("UTC"));
            UNPROTECT(1);
        } else {
            Rf_setAttrib(out, Rf_install("units"), Rf_mkString("secs"));
            Rf_setAttrib(out, R_ClassSymbol, Rf_mkString("difftime"));
        }
        UNPROTECT(1);
        return out;
    }
    case ZPB_WKT_STRUCT: return build_struct(ctx, m, msg);
    case ZPB_WKT_LISTVALUE: return build_list_value(ctx, m, msg);
    case ZPB_WKT_VALUE: return build_value_msg(ctx, m, msg);
    case ZPB_WKT_ANY: return build_any(ctx, m, msg);
    case ZPB_WKT_FIELDMASK: {
        const zpb_fielddef *paths = zpb_msgdef_field_by_number(m, 1);
        return build_array(ctx, paths, zpb_msg_get(msg, paths).array_val);
    }
    }

    int nf = zpb_msgdef_field_count(m);
    R_xlen_t n_ext = 0;
    {
        size_t iter = ZPB_MSG_ITER_BEGIN;
        const zpb_fielddef *f;
        zpb_value v;
        while (zpb_msg_next_extension(msg, m, ctx->pool, &f, &v, &iter)) n_ext++;
    }

    R_xlen_t cap = nf + n_ext, k = 0;
    SEXP out = PROTECT(Rf_allocVector(VECSXP, cap));
    SEXP names = PROTECT(Rf_allocVector(STRSXP, cap));

    for (int i = 0; i < nf; i++) {
        const zpb_fielddef *f = zpb_msgdef_field(m, i);
        zpb_value v = zpb_msg_get(msg, f);
        if (zpb_field_is_map(f)) {
            if (!ctx->defaults && zpb_map_size(v.map_val) == 0) continue;
        } else if (zpb_field_is_repeated(f)) {
            if (!ctx->defaults && zpb_array_size(v.array_val) == 0) continue;
        } else if (zpb_field_has_presence(f)) {
            if (!zpb_msg_has(msg, f)) continue;
        } else if (!ctx->defaults && is_default(f, v)) {
            continue;
        }
        SEXP x = build_field(ctx, f, v);
        if (x == NULL) {
            UNPROTECT(2);
            return NULL;
        }
        SET_VECTOR_ELT(out, k, x);
        SET_STRING_ELT(names, k, Rf_mkCharCE(zpb_field_name(f), CE_UTF8));
        k++;
    }

    size_t iter = ZPB_MSG_ITER_BEGIN;
    const zpb_fielddef *f;
    zpb_value v;
    while (k < cap && zpb_msg_next_extension(msg, m, ctx->pool, &f, &v, &iter)) {
        SEXP x = build_field(ctx, f, v);
        if (x == NULL) {
            UNPROTECT(2);
            return NULL;
        }
        SET_VECTOR_ELT(out, k, x);
        const char *full = zpb_field_full_name(f);
        size_t len = strlen(full) + 3;
        char *bracketed = R_alloc(len, 1);
        snprintf(bracketed, len, "[%s]", full);
        SET_STRING_ELT(names, k, Rf_mkCharCE(bracketed, CE_UTF8));
        k++;
    }

    int nprot = 2;
    if (k < cap) {
        out = PROTECT(Rf_lengthgets(out, k));
        names = PROTECT(Rf_lengthgets(names, k));
        nprot += 2;
    }
    Rf_setAttrib(out, R_NamesSymbol, names);
    if (ctx->keep_unknown) {
        SEXP unknown = unknown_bytes(msg);
        if (unknown != R_NilValue) {
            PROTECT(unknown);
            Rf_setAttrib(out, Rf_install("proto_unknown"), unknown);
            UNPROTECT(1);
        }
    }
    UNPROTECT(nprot);
    return out;
}

SEXP zpb_build(zpb_build_ctx *ctx, const zpb_msgdef *m, const zpb_msg *msg)
{
    return build_message(ctx, m, msg);
}
