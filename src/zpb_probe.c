#define R_NO_REMAP
#include <R.h>
#include <Rinternals.h>

#include "upb/ruby-upb.h"

/* Stage 1 probe, replaced by the shim in Stage 2. It builds a one-message
   FileDescriptorProto, encodes and decodes it, adds it to a symbol table and
   looks the message up: upb's encoder, decoder and defs in one call. No R
   API is called while upb is working; the result is built at the end. */
SEXP zpb_probe(void)
{
    int found = 0;
    upb_Arena *arena = upb_Arena_New();
    if (arena == NULL) Rf_error("upb_Arena_New failed");

    google_protobuf_FileDescriptorProto *file =
        google_protobuf_FileDescriptorProto_new(arena);
    google_protobuf_FileDescriptorProto_set_name(
        file, upb_StringView_FromString("probe.proto"));
    google_protobuf_DescriptorProto *msg =
        google_protobuf_FileDescriptorProto_add_message_type(file, arena);
    google_protobuf_DescriptorProto_set_name(
        msg, upb_StringView_FromString("Probe"));

    size_t len = 0;
    char *bytes = google_protobuf_FileDescriptorProto_serialize(file, arena, &len);
    google_protobuf_FileDescriptorProto *back =
        bytes ? google_protobuf_FileDescriptorProto_parse(bytes, len, arena) : NULL;

    if (back != NULL) {
        upb_DefPool *pool = upb_DefPool_New();
        upb_Status status;
        upb_Status_Clear(&status);
        if (pool != NULL) {
            found = upb_DefPool_AddFile(pool, back, &status) != NULL &&
                    upb_DefPool_FindMessageByName(pool, "Probe") != NULL;
            upb_DefPool_Free(pool);
        }
    }
    upb_Arena_Free(arena);
    return Rf_ScalarLogical(found);
}
