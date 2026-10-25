# Changelog

## zuproto 0.0.0.9000

- Initial CRAN submission.
- Package skeleton: identity, CI, and a native library that registers no
  routines yet.
- Bundles the upb runtime and utf8_range from Protocol Buffers v36.2, so
  no system protobuf library is needed.
- [`proto_pool()`](https://pedrobtz.github.io/zuproto/reference/proto_pool.md)
  and
  [`proto_pool_add()`](https://pedrobtz.github.io/zuproto/reference/proto_pool.md)
  load descriptor sets, with the well-known types built in;
  [`proto_types()`](https://pedrobtz.github.io/zuproto/reference/proto_types.md)
  and
  [`proto_fields()`](https://pedrobtz.github.io/zuproto/reference/proto_types.md)
  list what a pool holds, extensions included;
  [`zuproto_info()`](https://pedrobtz.github.io/zuproto/reference/zuproto_info.md)
  reports the bundled protobuf release.
- [`proto_decode()`](https://pedrobtz.github.io/zuproto/reference/proto_decode.md)
  decodes one message to a named list: every scalar type, enums as
  factors, repeated fields, maps, oneofs, extensions and the well-known
  types, with limits on size, nesting and memory.
- [`proto_encode()`](https://pedrobtz.github.io/zuproto/reference/proto_encode.md)
  encodes a named list as one message, deterministically, the inverse of
  [`proto_decode()`](https://pedrobtz.github.io/zuproto/reference/proto_decode.md);
  a value of the wrong form fails with a `zuproto_type_mismatch` naming
  the field.
