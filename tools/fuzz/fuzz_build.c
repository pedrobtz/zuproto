/* The R half (design sections 6 and 13): any bytes as one of
 * zpb_fuzz_types, through zuproto's own entry points with R embedded, so
 * the code that builds R values (src/zpb_build.c) and the encoder that
 * walks them (src/zpb_fill.c) run on what upb accepts. Invariants: a value
 * zpb_decode() builds re-encodes without error; the same bytes decode as a
 * one-row data frame and as a delimited stream without crashing.
 *
 * Each input runs under R_ToplevelExec(), so an R error is a reported
 * failure of that call, not a jump to R's top level. */
#include "fuzz.h"

#define R_NO_REMAP
#define CSTACK_DEFNS /* R_CStackLimit, which libFuzzer's stack makes moot */
#include <stdint.h>
#include <R.h>
#include <Rembedded.h>
#include <Rinterface.h>
#include <Rinternals.h>

#include <stdlib.h>

#include "zpb.h"

int LLVMFuzzerInitialize(int *argc, char ***argv);
int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size);

static SEXP pool_ptr = NULL;

static SEXP opts(const char **names, const double *values, int n, const char *field)
{
    SEXP out = PROTECT(Rf_allocVector(VECSXP, n + 1));
    SEXP nm = PROTECT(Rf_allocVector(STRSXP, n + 1));
    for (int i = 0; i < n; i++) {
        SET_VECTOR_ELT(out, i, Rf_ScalarReal(values[i]));
        SET_STRING_ELT(nm, i, Rf_mkChar(names[i]));
    }
    SET_VECTOR_ELT(out, n, Rf_mkString(field));
    SET_STRING_ELT(nm, n, Rf_mkChar("field"));
    Rf_setAttrib(out, R_NamesSymbol, nm);
    UNPROTECT(2);
    return out;
}

static SEXP get(SEXP list, const char *name)
{
    SEXP nm = Rf_getAttrib(list, R_NamesSymbol);
    for (R_xlen_t i = 0; i < XLENGTH(list); i++)
        if (strcmp(CHAR(STRING_ELT(nm, i)), name) == 0) return VECTOR_ELT(list, i);
    return R_NilValue;
}

int LLVMFuzzerInitialize(int *argc, char ***argv)
{
    (void) argc;
    (void) argv;
    char *rargv[] = {"R", "--vanilla", "--silent", "--no-echo"};
    if (!getenv("R_HOME")) {
        fprintf(stderr, "fuzz_build: R_HOME must be set\n");
        abort();
    }
    R_SignalHandlers = 0;
    Rf_initEmbeddedR(4, rargv);
    R_CStackLimit = (uintptr_t) -1;

    pool_ptr = zpb_pool_new();
    R_PreserveObject(pool_ptr);
    SEXP set = PROTECT(Rf_allocVector(RAWSXP, (R_xlen_t) zpb_fuzz_descriptors_len));
    memcpy(RAW(set), zpb_fuzz_descriptors, zpb_fuzz_descriptors_len);
    SEXP files = PROTECT(zpb_set_files(set));
    FUZZ_CHECK(TYPEOF(files) == VECSXP);
    SEXP bytes = VECTOR_ELT(files, 2);
    for (R_xlen_t i = 0; i < XLENGTH(bytes); i++)
        FUZZ_CHECK(zpb_pool_add_file(pool_ptr, VECTOR_ELT(bytes, i)) == R_NilValue);
    UNPROTECT(2);
    return 0;
}

typedef struct {
    const uint8_t *data;
    size_t size;
} input;

static void run(void *p)
{
    const input *in = (const input *) p;
    uint8_t sel = in->data[0];
    SEXP type = PROTECT(Rf_mkString(zpb_fuzz_types[sel % ZPB_FUZZ_NTYPES]));
    SEXP raw = PROTECT(Rf_allocVector(RAWSXP, (R_xlen_t) (in->size - 1)));
    if (in->size > 1) memcpy(RAW(raw), in->data + 1, in->size - 1);

    /* int64 as character keeps every value exact, so the re-encode is
     * expected to succeed; the high bits vary the other options. */
    const char *dn[] = {"int64", "enums", "defaults", "keep_unknown", "bytes_base64",
                        "max_depth", "arena_limit", "mode", "max_size", "max_rows",
                        "chunk_rows"};
    double dv[] = {1, (sel >> 5) % 3, (sel >> 7) & 1, 1, 0,
                   100, 4.0 * (double) in->size + 65536, 0, 1 << 20, 1e6, 1e6};
    SEXP dopts = PROTECT(opts(dn, dv, 11, ""));

    SEXP res = PROTECT(zpb_decode(pool_ptr, type, raw, dopts));
    SEXP value = get(res, "value");
    /* A decoded value re-encodes unless decoding made an NA: an enum number
     * the enum lacks (as a factor or a name), or an int32 of -2^31 (design
     * section 6.1), neither of which a repeated field can hold. The decode
     * counts both, so the invariant is checked when it counted neither. */
    if (get(res, "error") == R_NilValue && REAL(get(res, "precision_loss"))[0] == 0 &&
        REAL(get(res, "unknown_enum"))[0] == 0) {
        /* deterministic, check_required, write_unknown, ignore_extra */
        const int ev[] = {1, 0, 1, 0};
        SEXP eopts = PROTECT(Rf_allocVector(VECSXP, 4));
        for (int i = 0; i < 4; i++) SET_VECTOR_ELT(eopts, i, Rf_ScalarInteger(ev[i]));
        SEXP enc = PROTECT(zpb_encode(pool_ptr, type, value, eopts));
        FUZZ_CHECK(get(enc, "error") == R_NilValue);
        UNPROTECT(2);
    }

    SEXP list = PROTECT(Rf_allocVector(VECSXP, 1));
    SET_VECTOR_ELT(list, 0, raw);
    SEXP df = PROTECT(zpb_decode_df(pool_ptr, type, list, dopts));
    /* The single decode and the one-row frame agree on whether it decodes. */
    FUZZ_CHECK((get(df, "error") == R_NilValue) == (get(res, "error") == R_NilValue) ||
               strcmp(CHAR(STRING_ELT(get(res, "error"), 0)), "arena_limit") == 0 ||
               strcmp(CHAR(STRING_ELT(get(df, "error"), 0)), "arena_limit") == 0);

    SET_VECTOR_ELT(dopts, 7, Rf_ScalarReal(2)); /* mode 2: a delimited stream */
    zpb_decode_df(pool_ptr, type, raw, dopts);
    UNPROTECT(6);
}

int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size)
{
    FUZZ_CANARY(data, size);
    if (size < 1 || size > (1 << 16)) return 0;
    input in = {data, size};
    /* The entry points use R_alloc(), which R frees when a .Call returns;
     * called directly, that is this target's to do. */
    const void *vmax = vmaxget();
    R_ToplevelExec(run, &in);
    vmaxset(vmax);
    /* A full collection now and then, so R's heap growing between
     * collections is not taken for a leak under libFuzzer's RSS cap. */
    static unsigned long runs = 0;
    if (++runs % 1000 == 0) R_gc();
    return 0;
}
