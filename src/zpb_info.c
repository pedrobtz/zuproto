#include "zpb.h"
#include "zpb_version.h"

/* What zuproto_info() reports about the bundled upb. */
SEXP zpb_build_info(void)
{
    const char *names[] = {"protobuf_tag", "protobuf_commit", ""};
    SEXP out = PROTECT(Rf_mkNamed(VECSXP, names));
    SET_VECTOR_ELT(out, 0, Rf_mkString(ZPB_PROTOBUF_TAG));
    SET_VECTOR_ELT(out, 1, Rf_mkString(ZPB_PROTOBUF_COMMIT));
    UNPROTECT(1);
    return out;
}
