# zuproto 0.0.0.9000

* Initial CRAN submission.
* Package skeleton: identity, CI, and a native library that registers no
  routines yet.
* Bundles the upb runtime and utf8_range from Protocol Buffers v36.2, so
  no system protobuf library is needed.
* `proto_pool()` and `proto_pool_add()` load descriptor sets, with the
  well-known types built in; `proto_types()` and `proto_fields()` list what
  a pool holds, extensions included; `zuproto_info()` reports the bundled
  protobuf release.
