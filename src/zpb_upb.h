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
#include <stdlib.h>
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

/* ---- Decoding (design sections 4, 12 and 13) ---- */

typedef upb_Message zpb_msg;
typedef upb_Array zpb_array;
typedef upb_Map zpb_map;
typedef upb_EnumDef zpb_enumdef;
typedef upb_MessageValue zpb_value;

/* An allocator that refuses to hold more than `limit` bytes, so an arena
 * built on it caps what one decode can allocate (design section 12). It
 * must outlive the arena: upb frees the arena's blocks through it. */
typedef struct {
    upb_alloc base; /* first, so a upb_alloc* is a zpb_counting_alloc* */
    size_t used;
    size_t limit;
    int exceeded;
} zpb_counting_alloc;

static inline void *zpb_counting_func(upb_alloc *alloc, void *ptr,
                                      size_t oldsize, size_t size,
                                      size_t *actual_size)
{
    zpb_counting_alloc *ca = (zpb_counting_alloc *) alloc;
    size_t base = ca->used >= oldsize ? ca->used - oldsize : 0;
    if (size == 0) {
        free(ptr);
        ca->used = base;
        return NULL;
    }
    if (size > ca->limit || base > ca->limit - size) {
        ca->exceeded = 1;
        return NULL;
    }
    void *p = realloc(ptr, size);
    if (p == NULL) return NULL;
    ca->used = base + size;
    if (actual_size != NULL) *actual_size = size;
    return p;
}

static inline zpb_arena *zpb_arena_new_limited(zpb_counting_alloc *ca,
                                               size_t limit)
{
    ca->base.func = zpb_counting_func;
    ca->used = 0;
    ca->limit = limit;
    ca->exceeded = 0;
    return upb_Arena_Init(NULL, 0, &ca->base);
}

enum {
    ZPB_DECODE_OK = 0,
    ZPB_DECODE_MALFORMED,
    ZPB_DECODE_DEPTH,
    ZPB_DECODE_UTF8,
    ZPB_DECODE_MEMORY,
    ZPB_DECODE_OTHER
};

/* Decode buf as message type m into arena a, with m's pool's extensions.
 * Returns the message, or NULL with *status set. */
static inline const zpb_msg *zpb_decode_message(const zpb_defpool *p,
                                                const zpb_msgdef *m,
                                                const char *buf, size_t len,
                                                zpb_arena *a,
                                                uint16_t max_depth,
                                                int *status)
{
    const upb_MiniTable *mt = upb_MessageDef_MiniTable(m);
    upb_Message *msg = upb_Message_New(mt, a);
    if (msg == NULL) {
        *status = ZPB_DECODE_MEMORY;
        return NULL;
    }
    int options = (int) upb_DecodeOptions_MaxDepth(max_depth) |
                  kUpb_DecodeOption_AlwaysValidateUtf8;
    upb_DecodeStatus st = upb_Decode(buf, len, msg, mt,
                                     upb_DefPool_ExtensionRegistry(p),
                                     options, a);
    switch (st) {
    case kUpb_DecodeStatus_Ok: *status = ZPB_DECODE_OK; return msg;
    case kUpb_DecodeStatus_Malformed: *status = ZPB_DECODE_MALFORMED; break;
    case kUpb_DecodeStatus_MaxDepthExceeded: *status = ZPB_DECODE_DEPTH; break;
    case kUpb_DecodeStatus_BadUtf8: *status = ZPB_DECODE_UTF8; break;
    case kUpb_DecodeStatus_OutOfMemory: *status = ZPB_DECODE_MEMORY; break;
    default: *status = ZPB_DECODE_OTHER; break;
    }
    return NULL;
}

/* Reflection */

enum {
    ZPB_CTYPE_BOOL = kUpb_CType_Bool,
    ZPB_CTYPE_FLOAT = kUpb_CType_Float,
    ZPB_CTYPE_INT32 = kUpb_CType_Int32,
    ZPB_CTYPE_UINT32 = kUpb_CType_UInt32,
    ZPB_CTYPE_ENUM = kUpb_CType_Enum,
    ZPB_CTYPE_MESSAGE = kUpb_CType_Message,
    ZPB_CTYPE_DOUBLE = kUpb_CType_Double,
    ZPB_CTYPE_INT64 = kUpb_CType_Int64,
    ZPB_CTYPE_UINT64 = kUpb_CType_UInt64,
    ZPB_CTYPE_STRING = kUpb_CType_String,
    ZPB_CTYPE_BYTES = kUpb_CType_Bytes
};

static inline int zpb_field_ctype(const zpb_fielddef *f)
{
    return (int) upb_FieldDef_CType(f);
}

static inline bool zpb_field_is_repeated(const zpb_fielddef *f)
{
    return upb_FieldDef_IsRepeated(f);
}

static inline const zpb_msgdef *zpb_field_msgdef(const zpb_fielddef *f)
{
    return upb_FieldDef_MessageSubDef(f);
}

static inline const zpb_enumdef *zpb_field_enumdef(const zpb_fielddef *f)
{
    return upb_FieldDef_EnumSubDef(f);
}

static inline const zpb_fielddef *zpb_msgdef_field_by_number(const zpb_msgdef *m,
                                                             uint32_t n)
{
    return upb_MessageDef_FindFieldByNumber(m, n);
}

static inline bool zpb_msg_has(const zpb_msg *msg, const zpb_fielddef *f)
{
    return upb_Message_HasFieldByDef(msg, f);
}

static inline zpb_value zpb_msg_get(const zpb_msg *msg, const zpb_fielddef *f)
{
    return upb_Message_GetFieldByDef(msg, f);
}

/* Iterators start from these. */
#define ZPB_MSG_ITER_BEGIN ((size_t) kUpb_Message_Begin)
#define ZPB_MAP_ITER_BEGIN ((size_t) kUpb_Map_Begin)
#define ZPB_UNKNOWN_ITER_BEGIN ((uintptr_t) kUpb_Message_UnknownBegin)

/* The set extensions of msg, one per call; *iter starts at
 * ZPB_MSG_ITER_BEGIN. Fields that are not extensions are skipped. */
static inline bool zpb_msg_next_extension(const zpb_msg *msg,
                                          const zpb_msgdef *m,
                                          const zpb_defpool *p,
                                          const zpb_fielddef **f,
                                          zpb_value *v, size_t *iter)
{
    while (upb_Message_Next(msg, m, p, f, v, iter))
        if (upb_FieldDef_IsExtension(*f)) return true;
    return false;
}

/* The unknown-field bytes of msg, one chunk per call; *iter starts at
 * ZPB_UNKNOWN_ITER_BEGIN. */
static inline bool zpb_msg_next_unknown(const zpb_msg *msg, zpb_str *chunk,
                                        uintptr_t *iter)
{
    upb_StringView v;
    bool more = upb_Message_NextUnknown(msg, &v, iter);
    chunk->data = v.data;
    chunk->size = more ? v.size : 0;
    return more;
}

static inline size_t zpb_array_size(const zpb_array *a)
{
    return a != NULL ? upb_Array_Size(a) : 0;
}

static inline zpb_value zpb_array_get(const zpb_array *a, size_t i)
{
    return upb_Array_Get(a, i);
}

static inline size_t zpb_map_size(const zpb_map *m)
{
    return m != NULL ? upb_Map_Size(m) : 0;
}

/* The entries of a map, one per call; *iter starts at ZPB_MAP_ITER_BEGIN. */
static inline bool zpb_map_next(const zpb_map *m, zpb_value *k, zpb_value *v,
                                size_t *iter)
{
    return m != NULL && upb_Map_Next(m, k, v, iter);
}

/* Enums */

static inline int zpb_enum_value_count(const zpb_enumdef *e)
{
    return upb_EnumDef_ValueCount(e);
}

static inline const char *zpb_enum_value_name(const zpb_enumdef *e, int i)
{
    return upb_EnumValueDef_Name(upb_EnumDef_Value(e, i));
}

static inline int32_t zpb_enum_value_number(const zpb_enumdef *e, int i)
{
    return upb_EnumValueDef_Number(upb_EnumDef_Value(e, i));
}

/* Name of value n, or NULL if e has none. */
static inline const char *zpb_enum_name_of(const zpb_enumdef *e, int32_t n)
{
    const upb_EnumValueDef *v = upb_EnumDef_FindValueByNumber(e, n);
    return v != NULL ? upb_EnumValueDef_Name(v) : NULL;
}

/* Well-known types (design section 6.3) */

enum {
    ZPB_WKT_NONE = 0,
    ZPB_WKT_ANY,
    ZPB_WKT_FIELDMASK,
    ZPB_WKT_DURATION,
    ZPB_WKT_TIMESTAMP,
    ZPB_WKT_WRAPPER,
    ZPB_WKT_VALUE,
    ZPB_WKT_LISTVALUE,
    ZPB_WKT_STRUCT
};

static inline int zpb_msgdef_wkt(const zpb_msgdef *m)
{
    switch (upb_MessageDef_WellKnownType(m)) {
    case kUpb_WellKnown_Any: return ZPB_WKT_ANY;
    case kUpb_WellKnown_FieldMask: return ZPB_WKT_FIELDMASK;
    case kUpb_WellKnown_Duration: return ZPB_WKT_DURATION;
    case kUpb_WellKnown_Timestamp: return ZPB_WKT_TIMESTAMP;
    case kUpb_WellKnown_DoubleValue:
    case kUpb_WellKnown_FloatValue:
    case kUpb_WellKnown_Int64Value:
    case kUpb_WellKnown_UInt64Value:
    case kUpb_WellKnown_Int32Value:
    case kUpb_WellKnown_UInt32Value:
    case kUpb_WellKnown_StringValue:
    case kUpb_WellKnown_BytesValue:
    case kUpb_WellKnown_BoolValue: return ZPB_WKT_WRAPPER;
    case kUpb_WellKnown_Value: return ZPB_WKT_VALUE;
    case kUpb_WellKnown_ListValue: return ZPB_WKT_LISTVALUE;
    case kUpb_WellKnown_Struct: return ZPB_WKT_STRUCT;
    default: return ZPB_WKT_NONE;
    }
}

#endif
