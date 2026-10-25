#ifndef ZPB_UPB_H
#define ZPB_UPB_H

/* The shim (design section 9.3): the only file that includes upb or names
 * its symbols. tools/verify-vendor fails on upb anywhere else in src/, so a
 * re-vendor that changes upb's API is fixed here and nowhere else.
 *
 * Nothing here calls the R API. upb uses setjmp/longjmp internally, and an
 * R error unwinding through its frames would skip its cleanup. */

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

#include "upb/ruby-upb.h"

typedef upb_Arena zpb_arena;
typedef upb_DefPool zpb_defpool;
typedef upb_FileDef zpb_filedef;
typedef upb_MessageDef zpb_msgdef;
typedef upb_FieldDef zpb_fielddef;
typedef google_protobuf_FileDescriptorSet zpb_fdset;
typedef google_protobuf_FileDescriptorProto zpb_fdproto;

typedef struct {
    const char *data;
    size_t size;
} zpb_str;

static inline zpb_str zpb_str_from(upb_StringView v)
{
    zpb_str s = {v.data, v.size};
    return s;
}

/* Field labels, as in descriptor.proto. */
enum {
    ZPB_LABEL_OPTIONAL = kUpb_Label_Optional,
    ZPB_LABEL_REQUIRED = kUpb_Label_Required,
    ZPB_LABEL_REPEATED = kUpb_Label_Repeated
};

/* Arenas */

static inline zpb_arena *zpb_arena_new(void) { return upb_Arena_New(); }
static inline void zpb_arena_free(zpb_arena *a) { upb_Arena_Free(a); }

/* Symbol tables */

static inline zpb_defpool *zpb_defpool_new(void) { return upb_DefPool_New(); }
static inline void zpb_defpool_free(zpb_defpool *p) { upb_DefPool_Free(p); }

/* Parse and add one serialised FileDescriptorProto. Returns NULL on failure
 * with upb's message copied into err (always NUL-terminated). */
static inline const zpb_filedef *zpb_defpool_add_file(zpb_defpool *p,
                                                      const char *buf,
                                                      size_t len,
                                                      zpb_arena *a,
                                                      char *err,
                                                      size_t err_len)
{
    err[0] = '\0';
    const zpb_fdproto *f = google_protobuf_FileDescriptorProto_parse(buf, len, a);
    if (f == NULL) {
        snprintf(err, err_len, "not a valid FileDescriptorProto");
        return NULL;
    }
    upb_Status status;
    upb_Status_Clear(&status);
    const zpb_filedef *def = upb_DefPool_AddFile(p, f, &status);
    if (def == NULL)
        snprintf(err, err_len, "%s", upb_Status_ErrorMessage(&status));
    return def;
}

static inline const zpb_filedef *zpb_defpool_find_file(const zpb_defpool *p,
                                                       const char *name)
{
    return upb_DefPool_FindFileByName(p, name);
}

static inline const zpb_msgdef *zpb_defpool_find_message(const zpb_defpool *p,
                                                         const char *name)
{
    return upb_DefPool_FindMessageByName(p, name);
}

/* The extensions of m the pool knows, copied into out (at most cap).
 * Returns how many there are, which may exceed cap. upb returns a malloc'd
 * array; it is freed here, before the caller touches R. Returns -1 if that
 * allocation failed. */
static inline ptrdiff_t zpb_defpool_extensions(const zpb_defpool *p,
                                               const zpb_msgdef *m,
                                               const zpb_fielddef **out,
                                               size_t cap)
{
    size_t n = 0;
    const upb_FieldDef **all = upb_DefPool_GetAllExtensions(p, m, &n);
    if (all == NULL && n > 0) return -1;
    for (size_t i = 0; i < n && i < cap; i++) out[i] = all[i];
    upb_gfree((void *) all);
    return (ptrdiff_t) n;
}

/* FileDescriptorSet */

static inline const zpb_fdset *zpb_fdset_parse(const char *buf, size_t len,
                                               zpb_arena *a)
{
    return google_protobuf_FileDescriptorSet_parse(buf, len, a);
}

static inline size_t zpb_fdset_count(const zpb_fdset *s)
{
    size_t n = 0;
    google_protobuf_FileDescriptorSet_file(s, &n);
    return n;
}

static inline const zpb_fdproto *zpb_fdset_file(const zpb_fdset *s, size_t i)
{
    size_t n = 0;
    const zpb_fdproto *const *files = google_protobuf_FileDescriptorSet_file(s, &n);
    return i < n ? files[i] : NULL;
}

static inline zpb_str zpb_fdproto_name(const zpb_fdproto *f)
{
    return zpb_str_from(google_protobuf_FileDescriptorProto_name(f));
}

static inline size_t zpb_fdproto_dep_count(const zpb_fdproto *f)
{
    size_t n = 0;
    google_protobuf_FileDescriptorProto_dependency(f, &n);
    return n;
}

static inline zpb_str zpb_fdproto_dep(const zpb_fdproto *f, size_t i)
{
    size_t n = 0;
    const upb_StringView *deps = google_protobuf_FileDescriptorProto_dependency(f, &n);
    return zpb_str_from(deps[i]);
}

/* Serialised bytes in the arena, or NULL. */
static inline char *zpb_fdproto_serialize(const zpb_fdproto *f, zpb_arena *a,
                                          size_t *len)
{
    return google_protobuf_FileDescriptorProto_serialize(f, a, len);
}

/* Files and messages */

static inline const char *zpb_filedef_name(const zpb_filedef *f)
{
    return upb_FileDef_Name(f);
}

static inline int zpb_filedef_message_count(const zpb_filedef *f)
{
    return upb_FileDef_TopLevelMessageCount(f);
}

static inline const zpb_msgdef *zpb_filedef_message(const zpb_filedef *f, int i)
{
    return upb_FileDef_TopLevelMessage(f, i);
}

static inline int zpb_msgdef_nested_count(const zpb_msgdef *m)
{
    return upb_MessageDef_NestedMessageCount(m);
}

static inline const zpb_msgdef *zpb_msgdef_nested(const zpb_msgdef *m, int i)
{
    return upb_MessageDef_NestedMessage(m, i);
}

static inline const char *zpb_msgdef_full_name(const zpb_msgdef *m)
{
    return upb_MessageDef_FullName(m);
}

static inline const char *zpb_msgdef_file_name(const zpb_msgdef *m)
{
    return upb_FileDef_Name(upb_MessageDef_File(m));
}

static inline bool zpb_msgdef_is_map_entry(const zpb_msgdef *m)
{
    return upb_MessageDef_IsMapEntry(m);
}

static inline int zpb_msgdef_field_count(const zpb_msgdef *m)
{
    return upb_MessageDef_FieldCount(m);
}

static inline const zpb_fielddef *zpb_msgdef_field(const zpb_msgdef *m, int i)
{
    return upb_MessageDef_Field(m, i);
}

/* Fields */

static inline const char *zpb_field_name(const zpb_fielddef *f)
{
    return upb_FieldDef_Name(f);
}

static inline const char *zpb_field_full_name(const zpb_fielddef *f)
{
    return upb_FieldDef_FullName(f);
}

static inline uint32_t zpb_field_number(const zpb_fielddef *f)
{
    return upb_FieldDef_Number(f);
}

/* The descriptor.proto type number, 1 (double) to 18 (sint64). */
static inline int zpb_field_type(const zpb_fielddef *f)
{
    return (int) upb_FieldDef_Type(f);
}

static inline int zpb_field_label(const zpb_fielddef *f)
{
    return (int) upb_FieldDef_Label(f);
}

/* Full name of the message or enum type, or NULL for scalars. */
static inline const char *zpb_field_type_name(const zpb_fielddef *f)
{
    const upb_MessageDef *m = upb_FieldDef_MessageSubDef(f);
    if (m != NULL) return upb_MessageDef_FullName(m);
    const upb_EnumDef *e = upb_FieldDef_EnumSubDef(f);
    return e != NULL ? upb_EnumDef_FullName(e) : NULL;
}

/* Name of the oneof, or NULL; proto3 `optional` synthetic oneofs excluded. */
static inline const char *zpb_field_oneof(const zpb_fielddef *f)
{
    const upb_OneofDef *o = upb_FieldDef_RealContainingOneof(f);
    return o != NULL ? upb_OneofDef_Name(o) : NULL;
}

static inline const char *zpb_field_json_name(const zpb_fielddef *f)
{
    return upb_FieldDef_JsonName(f);
}

static inline bool zpb_field_has_presence(const zpb_fielddef *f)
{
    return upb_FieldDef_HasPresence(f);
}

static inline bool zpb_field_is_packed(const zpb_fielddef *f)
{
    return upb_FieldDef_IsPacked(f);
}

static inline bool zpb_field_is_map(const zpb_fielddef *f)
{
    return upb_FieldDef_IsMap(f);
}

static inline bool zpb_field_is_extension(const zpb_fielddef *f)
{
    return upb_FieldDef_IsExtension(f);
}

#endif
