#ifndef ZPB_H
#define ZPB_H

#define R_NO_REMAP
#include <R.h>
#include <Rinternals.h>

/* .Call entry points, registered in init.c. */
SEXP zpb_build_info(void);
SEXP zpb_pool_new(void);
SEXP zpb_pool_is_valid(SEXP ptr);
SEXP zpb_set_files(SEXP raw);
SEXP zpb_pool_add_file(SEXP ptr, SEXP raw);
SEXP zpb_pool_types(SEXP ptr, SEXP files);
SEXP zpb_pool_fields(SEXP ptr, SEXP type);
SEXP zpb_decode(SEXP ptr, SEXP type, SEXP raw, SEXP opts);
SEXP zpb_encode(SEXP ptr, SEXP type, SEXP x, SEXP opts);
SEXP zpb_decode_df(SEXP ptr, SEXP type, SEXP x, SEXP opts);
SEXP zpb_frame_delimited(SEXP msgs);

#endif
