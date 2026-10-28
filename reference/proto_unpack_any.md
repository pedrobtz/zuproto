# Pack and unpack an Any

`proto_unpack_any()` decodes the message a `google.protobuf.Any` packs,
as
[`proto_decode()`](https://pedrobtz.github.io/zuproto/reference/proto_decode.md)
decodes any message. The type is the part of `type_url` after its last
`/`, and must be in the pool. `proto_pack_any()` is the inverse: it
encodes a message with
[`proto_encode()`](https://pedrobtz.github.io/zuproto/reference/proto_encode.md)
and names its type, giving a value to set an `Any` field to.

## Usage

``` r
proto_unpack_any(x, pool, ...)

proto_pack_any(x, type, pool, prefix = "type.googleapis.com/", ...)
```

## Arguments

- x:

  For `proto_unpack_any()`, an `Any` as
  [`proto_decode()`](https://pedrobtz.github.io/zuproto/reference/proto_decode.md)
  returns it: a list of `type_url` and `value` (the packed bytes). For
  `proto_pack_any()`, the message, as
  [`proto_encode()`](https://pedrobtz.github.io/zuproto/reference/proto_encode.md)
  takes it.

- pool:

  A pool from
  [`proto_pool()`](https://pedrobtz.github.io/zuproto/reference/proto_pool.md)
  holding the packed type.

- ...:

  Passed to
  [`proto_decode()`](https://pedrobtz.github.io/zuproto/reference/proto_decode.md)
  or
  [`proto_encode()`](https://pedrobtz.github.io/zuproto/reference/proto_encode.md).

- type:

  The message type's full name.

- prefix:

  The `type_url` before the type name. Protobuf's JSON mapping and most
  runtimes expect the default.

## Value

`proto_unpack_any()`: the packed message, as
[`proto_decode()`](https://pedrobtz.github.io/zuproto/reference/proto_decode.md)
returns it. `proto_pack_any()`: an `Any`, a list of `type_url` and
`value`.

## Examples

``` r
pool <- proto_pool()
any <- proto_pack_any(42L, "google.protobuf.Int32Value", pool)
any$type_url
#> [1] "type.googleapis.com/google.protobuf.Int32Value"
proto_unpack_any(any, pool)
#> [1] 42
```
