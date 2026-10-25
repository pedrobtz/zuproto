#include "zpb.h"
#include <R_ext/Rdynload.h>
#include <R_ext/Visibility.h>

static const R_CallMethodDef CallEntries[] = {
    {"zpb_build_info", (DL_FUNC) &zpb_build_info, 0},
    {"zpb_pool_new", (DL_FUNC) &zpb_pool_new, 0},
    {"zpb_pool_is_valid", (DL_FUNC) &zpb_pool_is_valid, 1},
    {"zpb_set_files", (DL_FUNC) &zpb_set_files, 1},
    {"zpb_pool_add_file", (DL_FUNC) &zpb_pool_add_file, 2},
    {"zpb_pool_types", (DL_FUNC) &zpb_pool_types, 2},
    {"zpb_pool_fields", (DL_FUNC) &zpb_pool_fields, 2},
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
