# Package index

## Pools

Load descriptor sets and see the types they hold.

- [`proto_pool()`](https://pedrobtz.github.io/zuproto/reference/proto_pool.md)
  [`proto_pool_add()`](https://pedrobtz.github.io/zuproto/reference/proto_pool.md)
  : Descriptor pools
- [`proto_types()`](https://pedrobtz.github.io/zuproto/reference/proto_types.md)
  [`proto_fields()`](https://pedrobtz.github.io/zuproto/reference/proto_types.md)
  : Message types and their fields
- [`proto_enums()`](https://pedrobtz.github.io/zuproto/reference/proto_enums.md)
  : Enum values

## One message

Decode and encode a single message.

- [`proto_decode()`](https://pedrobtz.github.io/zuproto/reference/proto_decode.md)
  : Decode one Protocol Buffers message
- [`proto_encode()`](https://pedrobtz.github.io/zuproto/reference/proto_encode.md)
  : Encode one Protocol Buffers message
- [`proto_unpack_any()`](https://pedrobtz.github.io/zuproto/reference/proto_unpack_any.md)
  [`proto_pack_any()`](https://pedrobtz.github.io/zuproto/reference/proto_unpack_any.md)
  : Pack and unpack an Any

## Many messages

Data frames from many messages, a repeated field or a stream.

- [`proto_decode_df()`](https://pedrobtz.github.io/zuproto/reference/proto_decode_df.md)
  : Decode many messages into a data frame
- [`proto_read_delimited()`](https://pedrobtz.github.io/zuproto/reference/proto_read_delimited.md)
  [`proto_write_delimited()`](https://pedrobtz.github.io/zuproto/reference/proto_read_delimited.md)
  : Length-delimited streams

## JSON

- [`proto_to_json()`](https://pedrobtz.github.io/zuproto/reference/proto_to_json.md)
  [`proto_from_json()`](https://pedrobtz.github.io/zuproto/reference/proto_to_json.md)
  : Protobuf JSON

## Package

- [`zuproto_info()`](https://pedrobtz.github.io/zuproto/reference/zuproto_info.md)
  : Build information
- [`zuproto-conditions`](https://pedrobtz.github.io/zuproto/reference/zuproto-conditions.md)
  : Conditions raised by zuproto
- [`zuproto`](https://pedrobtz.github.io/zuproto/reference/zuproto-package.md)
  [`zuproto-package`](https://pedrobtz.github.io/zuproto/reference/zuproto-package.md)
  : zuproto: 'Protocol Buffers' Decoding and Encoding with 'upb'
