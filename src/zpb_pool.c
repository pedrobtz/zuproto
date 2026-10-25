#define R_NO_REMAP
#include <R.h>
#include <Rinternals.h>

#include "zpb.h"
#include "zpb_upb.h"

/* Descriptor pools (design section 8). A pool is a finalised external
 * pointer to a symbol table; R/pool.R keeps the files added to it and
 * decides the order, conflicts and missing imports. The functions here
 * return plain values or an error string, and R raises the condition. */

static void pool_finalize(SEXP ptr)
{
    zpb_defpool *p = (zpb_defpool *) R_ExternalPtrAddr(ptr);
    if (p != NULL) {
        zpb_defpool_free(p);
        R_ClearExternalPtr(ptr);
    }
}

static void arena_finalize(SEXP ptr)
{
    zpb_arena *a = (zpb_arena *) R_ExternalPtrAddr(ptr);
    if (a != NULL) {
        zpb_arena_free(a);
        R_ClearExternalPtr(ptr);
    }
}

/* An arena owned by a finalised external pointer from the moment it
 * exists (design section 13), so an R error while values are built from
 * it frees it through the finaliser. The caller PROTECTs the result and
 * calls zpb_arena_release() when done. */
SEXP zpb_arena_xptr(zpb_arena **out)
{
    zpb_arena *a = zpb_arena_new();
    if (a == NULL) Rf_error("zuproto: out of memory creating an arena");
    SEXP ptr = PROTECT(R_MakeExternalPtr(a, R_NilValue, R_NilValue));
    R_RegisterCFinalizerEx(ptr, arena_finalize, TRUE);
    UNPROTECT(1);
    *out = a;
    return ptr;
}

void zpb_arena_release(SEXP ptr)
{
    arena_finalize(ptr);
}

const zpb_defpool *zpb_pool_get(SEXP ptr)
{
    if (TYPEOF(ptr) != EXTPTRSXP || R_ExternalPtrTag(ptr) != Rf_install("zpb_pool"))
        Rf_error("zuproto: not a pool pointer");
    zpb_defpool *p = (zpb_defpool *) R_ExternalPtrAddr(ptr);
    if (p == NULL) Rf_error("zuproto: the pool's pointer is null");
    return p;
}

SEXP zpb_pool_new(void)
{
    zpb_defpool *p = zpb_defpool_new();
    if (p == NULL) Rf_error("zuproto: out of memory creating a pool");
    SEXP ptr = PROTECT(R_MakeExternalPtr(p, Rf_install("zpb_pool"), R_NilValue));
    R_RegisterCFinalizerEx(ptr, pool_finalize, TRUE);
    UNPROTECT(1);
    return ptr;
}

SEXP zpb_pool_is_valid(SEXP ptr)
{
    return Rf_ScalarLogical(TYPEOF(ptr) == EXTPTRSXP &&
                            R_ExternalPtrTag(ptr) == Rf_install("zpb_pool") &&
                            R_ExternalPtrAddr(ptr) != NULL);
}

static SEXP mk_str(zpb_str s)
{
    return Rf_mkCharLenCE(s.data, (int) s.size, CE_UTF8);
}

/* The files of a serialised FileDescriptorSet: a list of `name`
 * (character), `deps` (list of character) and `bytes` (list of raw, each
 * file re-serialised). A string instead means the bytes are not a set. */
SEXP zpb_set_files(SEXP raw)
{
    zpb_arena *a;
    SEXP aptr = PROTECT(zpb_arena_xptr(&a));
    const zpb_fdset *set =
        zpb_fdset_parse((const char *) RAW(raw), (size_t) XLENGTH(raw), a);
    if (set == NULL) {
        zpb_arena_release(aptr);
        UNPROTECT(1);
        return Rf_mkString("not a serialised FileDescriptorSet");
    }

    size_t n = zpb_fdset_count(set);
    const char *names[] = {"name", "deps", "bytes", ""};
    SEXP out = PROTECT(Rf_mkNamed(VECSXP, names));
    SEXP name = PROTECT(Rf_allocVector(STRSXP, (R_xlen_t) n));
    SEXP deps = PROTECT(Rf_allocVector(VECSXP, (R_xlen_t) n));
    SEXP bytes = PROTECT(Rf_allocVector(VECSXP, (R_xlen_t) n));
    SET_VECTOR_ELT(out, 0, name);
    SET_VECTOR_ELT(out, 1, deps);
    SET_VECTOR_ELT(out, 2, bytes);

    for (size_t i = 0; i < n; i++) {
        const zpb_fdproto *f = zpb_fdset_file(set, i);
        SET_STRING_ELT(name, (R_xlen_t) i, mk_str(zpb_fdproto_name(f)));

        size_t nd = zpb_fdproto_dep_count(f);
        SEXP d = Rf_allocVector(STRSXP, (R_xlen_t) nd);
        SET_VECTOR_ELT(deps, (R_xlen_t) i, d);
        for (size_t j = 0; j < nd; j++)
            SET_STRING_ELT(d, (R_xlen_t) j, mk_str(zpb_fdproto_dep(f, j)));

        size_t len = 0;
        char *buf = zpb_fdproto_serialize(f, a, &len);
        if (buf == NULL) Rf_error("zuproto: out of memory serialising a file");
        SEXP b = Rf_allocVector(RAWSXP, (R_xlen_t) len);
        SET_VECTOR_ELT(bytes, (R_xlen_t) i, b);
        if (len > 0) memcpy(RAW(b), buf, len);
    }

    zpb_arena_release(aptr);
    UNPROTECT(5);
    return out;
}

/* Add one serialised FileDescriptorProto. NULL on success, else upb's
 * message. */
SEXP zpb_pool_add_file(SEXP ptr, SEXP raw)
{
    zpb_defpool *p = (zpb_defpool *) zpb_pool_get(ptr);
    char err[1024];
    zpb_arena *a = zpb_arena_new();
    if (a == NULL) Rf_error("zuproto: out of memory creating an arena");
    const zpb_filedef *def = zpb_defpool_add_file(
        p, (const char *) RAW(raw), (size_t) XLENGTH(raw), a, err, sizeof err);
    zpb_arena_free(a);
    return def != NULL ? R_NilValue : Rf_mkString(err);
}

/* Message types, depth-first, map entries left out. */
typedef struct {
    const zpb_msgdef **items;
    size_t n, cap;
} msg_list;

static void collect(const zpb_msgdef *m, msg_list *out)
{
    if (zpb_msgdef_is_map_entry(m)) return;
    if (out->n == out->cap) {
        size_t cap = out->cap ? 2 * out->cap : 64;
        const zpb_msgdef **items =
            (const zpb_msgdef **) R_alloc(cap, sizeof *items);
        if (out->n) memcpy(items, out->items, out->n * sizeof *items);
        out->items = items;
        out->cap = cap;
    }
    out->items[out->n++] = m;
    for (int i = 0; i < zpb_msgdef_nested_count(m); i++)
        collect(zpb_msgdef_nested(m, i), out);
}

SEXP zpb_pool_types(SEXP ptr, SEXP files)
{
    const zpb_defpool *p = zpb_pool_get(ptr);
    msg_list all = {NULL, 0, 0};
    for (R_xlen_t i = 0; i < XLENGTH(files); i++) {
        const zpb_filedef *f =
            zpb_defpool_find_file(p, Rf_translateCharUTF8(STRING_ELT(files, i)));
        if (f == NULL) continue;
        for (int j = 0; j < zpb_filedef_message_count(f); j++)
            collect(zpb_filedef_message(f, j), &all);
    }

    const char *names[] = {"name", "file", "fields", ""};
    SEXP out = PROTECT(Rf_mkNamed(VECSXP, names));
    SEXP name = PROTECT(Rf_allocVector(STRSXP, (R_xlen_t) all.n));
    SEXP file = PROTECT(Rf_allocVector(STRSXP, (R_xlen_t) all.n));
    SEXP fields = PROTECT(Rf_allocVector(INTSXP, (R_xlen_t) all.n));
    for (size_t i = 0; i < all.n; i++) {
        SET_STRING_ELT(name, (R_xlen_t) i,
                       Rf_mkCharCE(zpb_msgdef_full_name(all.items[i]), CE_UTF8));
        SET_STRING_ELT(file, (R_xlen_t) i,
                       Rf_mkCharCE(zpb_msgdef_file_name(all.items[i]), CE_UTF8));
        INTEGER(fields)[i] = zpb_msgdef_field_count(all.items[i]);
    }
    SET_VECTOR_ELT(out, 0, name);
    SET_VECTOR_ELT(out, 1, file);
    SET_VECTOR_ELT(out, 2, fields);
    UNPROTECT(4);
    return out;
}

/* descriptor.proto's type names, by type number. */
static const char *const type_names[] = {
    NULL,      "double",  "float",    "int64",    "uint64",  "int32",
    "fixed64", "fixed32", "bool",     "string",   "group",   "message",
    "bytes",   "uint32",  "enum",     "sfixed32", "sfixed64", "sint32",
    "sint64"};

static SEXP opt_str(const char *s)
{
    return s != NULL ? Rf_mkCharCE(s, CE_UTF8) : NA_STRING;
}

/* The fields of one message type, then the extensions the pool knows for
 * it, as columns. NULL if the type is not in the pool. */
SEXP zpb_pool_fields(SEXP ptr, SEXP type)
{
    const zpb_defpool *p = zpb_pool_get(ptr);
    const zpb_msgdef *m =
        zpb_defpool_find_message(p, Rf_translateCharUTF8(STRING_ELT(type, 0)));
    if (m == NULL) return R_NilValue;

    int nf = zpb_msgdef_field_count(m);
    ptrdiff_t ne = zpb_defpool_extensions(p, m, NULL, 0);
    if (ne < 0) Rf_error("zuproto: out of memory listing extensions");
    const zpb_fielddef **ext = NULL;
    if (ne > 0) {
        ext = (const zpb_fielddef **) R_alloc((size_t) ne, sizeof *ext);
        ne = zpb_defpool_extensions(p, m, ext, (size_t) ne);
        if (ne < 0) Rf_error("zuproto: out of memory listing extensions");
    }
    R_xlen_t n = nf + (R_xlen_t) ne;

    const char *names[] = {"name",      "number", "type",     "label",
                           "type_name", "oneof",  "json_name", "presence",
                           "packed",    "map",    "extension", ""};
    SEXP out = PROTECT(Rf_mkNamed(VECSXP, names));
    SEXP col[11];
    SEXPTYPE types[] = {STRSXP, INTSXP, STRSXP, STRSXP, STRSXP, STRSXP,
                        STRSXP, LGLSXP, LGLSXP, LGLSXP, LGLSXP};
    for (int k = 0; k < 11; k++) {
        col[k] = Rf_allocVector(types[k], n);
        SET_VECTOR_ELT(out, k, col[k]);
    }

    for (R_xlen_t i = 0; i < n; i++) {
        const zpb_fielddef *f =
            i < nf ? zpb_msgdef_field(m, (int) i) : ext[i - nf];
        int is_ext = zpb_field_is_extension(f);
        int t = zpb_field_type(f);
        int label = zpb_field_label(f);

        if (is_ext) {
            const char *full = zpb_field_full_name(f);
            size_t len = strlen(full) + 3;
            char *bracketed = R_alloc(len, 1);
            snprintf(bracketed, len, "[%s]", full);
            SET_STRING_ELT(col[0], i, Rf_mkCharCE(bracketed, CE_UTF8));
        } else {
            SET_STRING_ELT(col[0], i, Rf_mkCharCE(zpb_field_name(f), CE_UTF8));
        }
        INTEGER(col[1])[i] = (int) zpb_field_number(f);
        SET_STRING_ELT(col[2], i,
                       opt_str(t >= 1 && t <= 18 ? type_names[t] : NULL));
        SET_STRING_ELT(col[3], i,
                       Rf_mkChar(label == ZPB_LABEL_REPEATED   ? "repeated"
                                 : label == ZPB_LABEL_REQUIRED ? "required"
                                                               : "optional"));
        SET_STRING_ELT(col[4], i, opt_str(zpb_field_type_name(f)));
        SET_STRING_ELT(col[5], i, opt_str(zpb_field_oneof(f)));
        SET_STRING_ELT(col[6], i, opt_str(zpb_field_json_name(f)));
        LOGICAL(col[7])[i] = zpb_field_has_presence(f);
        LOGICAL(col[8])[i] = zpb_field_is_packed(f);
        LOGICAL(col[9])[i] = zpb_field_is_map(f);
        LOGICAL(col[10])[i] = is_ext;
    }
    UNPROTECT(1);
    return out;
}
