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
