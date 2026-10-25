#define R_NO_REMAP
#include <R.h>
#include <Rinternals.h>
#include <R_ext/Rdynload.h>
#include <R_ext/Visibility.h>

SEXP zpb_probe(void);

static const R_CallMethodDef CallEntries[] = {
    {"zpb_probe", (DL_FUNC) &zpb_probe, 0},
    {NULL, NULL, 0}
};

/* Built with $(C_VISIBILITY) (src/Makevars), so this is the one exported
   symbol (design section 3, R3). */
void attribute_visible R_init_zuproto(DllInfo *dll)
{
    R_registerRoutines(dll, NULL, CallEntries, NULL, NULL);
    R_useDynamicSymbols(dll, FALSE);
    R_forceSymbols(dll, TRUE);
}
