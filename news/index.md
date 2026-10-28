# Changelog

## zuproto 0.1.0

- Initial CRAN submission.
- Bundles the upb runtime and utf8_range from Protocol Buffers v36.2, so
  no system protobuf library is needed.
- [`proto_pool()`](https://pedrobtz.github.io/zuproto/reference/proto_pool.md)
  and
  [`proto_pool_add()`](https://pedrobtz.github.io/zuproto/reference/proto_pool.md)
  load descriptor sets, with the well-known types built in;
  [`proto_types()`](https://pedrobtz.github.io/zuproto/reference/proto_types.md)
  and
  [`proto_fields()`](https://pedrobtz.github.io/zuproto/reference/proto_types.md)
  list what a pool holds, extensions included, and
  [`proto_enums()`](https://pedrobtz.github.io/zuproto/reference/proto_enums.md)
  an enum’s values
  ([\#61](https://github.com/pedrobtz/zuproto/issues/61));
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
- [`proto_decode_df()`](https://pedrobtz.github.io/zuproto/reference/proto_decode_df.md)
  decodes many messages, or the elements of one message’s repeated field
  (`field =`), into a data frame built column by column.
  [`proto_read_delimited()`](https://pedrobtz.github.io/zuproto/reference/proto_read_delimited.md)
  and
  [`proto_write_delimited()`](https://pedrobtz.github.io/zuproto/reference/proto_read_delimited.md)
  read and write length-delimited streams, in chunks with `each`.
- [`proto_to_json()`](https://pedrobtz.github.io/zuproto/reference/proto_to_json.md)
  and
  [`proto_from_json()`](https://pedrobtz.github.io/zuproto/reference/proto_to_json.md)
  convert to and from protobuf’s canonical JSON mapping through upb, and
  to and from R values through zujson when it is installed.
  [`proto_unpack_any()`](https://pedrobtz.github.io/zuproto/reference/proto_unpack_any.md)
  decodes an `Any`, and
  [`proto_pack_any()`](https://pedrobtz.github.io/zuproto/reference/proto_unpack_any.md)
  builds one ([\#60](https://github.com/pedrobtz/zuproto/issues/60)).
  `int64 = "integer64"` decodes 64-bit fields as bit64 vectors.
- Encoding accepts NaN in `double` and `float` fields, writes `NULL` in
  a `Value` field as JSON null, and takes any `Timestamp` or `Duration`
  the binary format allows; the JSON mapping’s narrower ranges are
  enforced by
  [`proto_to_json()`](https://pedrobtz.github.io/zuproto/reference/proto_to_json.md).
- [`proto_decode()`](https://pedrobtz.github.io/zuproto/reference/proto_decode.md),
  [`proto_encode()`](https://pedrobtz.github.io/zuproto/reference/proto_encode.md)
  and
  [`proto_to_json()`](https://pedrobtz.github.io/zuproto/reference/proto_to_json.md)
  skip checking arguments left at their defaults: a small message
  decodes in about a third of the time.
- Decoding gives `NaN`, never `NA`, for a NaN on the wire, and warns
  (`zuproto_precision_loss`) for Timestamp and Duration seconds beyond
  2^53.
- The memory a decode may use is bounded by what a message of its type
  can need, so valid input, such as a batch of thousands of small
  messages, is never refused for it.
  [`proto_to_json()`](https://pedrobtz.github.io/zuproto/reference/proto_to_json.md)
  bounds every `Any` it writes by `max_depth`.
- [`proto_encode()`](https://pedrobtz.github.io/zuproto/reference/proto_encode.md)
  nests as deep as
  [`proto_decode()`](https://pedrobtz.github.io/zuproto/reference/proto_decode.md)
  accepts (1000 levels), and refuses strings that are not valid UTF-8, a
  `Date` for a `Timestamp`, and a field given twice.
  [`proto_write_delimited()`](https://pedrobtz.github.io/zuproto/reference/proto_read_delimited.md)
  writes back frames whose nested messages hold oneofs. Failures that
  are no user error are a `zuproto_internal_error`.
