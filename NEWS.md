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
* `proto_decode()` decodes one message to a named list: every scalar type,
  enums as factors, repeated fields, maps, oneofs, extensions and the
  well-known types, with limits on size, nesting and memory.
* `proto_encode()` encodes a named list as one message, deterministically,
  the inverse of `proto_decode()`; a value of the wrong form fails with a
  `zuproto_type_mismatch` naming the field.
* `proto_decode_df()` decodes many messages, or the elements of one
  message's repeated field (`field =`), into a data frame built column by
  column. `proto_read_delimited()` and `proto_write_delimited()` read and
  write length-delimited streams, in chunks with `each`.
* `proto_to_json()` and `proto_from_json()` convert to and from protobuf's
  canonical JSON mapping through upb, and to and from R values through
  zujson when it is installed. `proto_unpack_any()` decodes an `Any`.
  `int64 = "integer64"` decodes 64-bit fields as bit64 vectors.
* Encoding accepts NaN in `double` and `float` fields, writes `NULL` in a
  `Value` field as JSON null, and takes any `Timestamp` or `Duration` the
  binary format allows; the JSON mapping's narrower ranges are enforced by
  `proto_to_json()`.
* `proto_decode()`, `proto_encode()` and `proto_to_json()` skip checking
  arguments left at their defaults: a small message decodes in about a
  third of the time.
* Decoding gives `NaN`, never `NA`, for a NaN on the wire, and warns
  (`zuproto_precision_loss`) for Timestamp and Duration seconds beyond 2^53.
