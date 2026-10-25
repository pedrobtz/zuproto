# Unpack an Any

Decodes the message a `google.protobuf.Any` packs, as
[`proto_decode()`](https://pedrobtz.github.io/zuproto/reference/proto_decode.md)
decodes any message. The type is the part of `type_url` after its last
`/`, and must be in the pool.

## Usage

``` r
proto_unpack_any(x, pool, ...)
```

## Arguments

- x:

  An `Any` as
  [`proto_decode()`](https://pedrobtz.github.io/zuproto/reference/proto_decode.md)
  returns it: a list of `type_url` and `value` (the packed bytes).

- pool:

  A pool from
  [`proto_pool()`](https://pedrobtz.github.io/zuproto/reference/proto_pool.md)
  holding the packed type.

- ...:

  Passed to
  [`proto_decode()`](https://pedrobtz.github.io/zuproto/reference/proto_decode.md).

## Value

The packed message, as
[`proto_decode()`](https://pedrobtz.github.io/zuproto/reference/proto_decode.md)
returns it.

## Examples

``` r
pool <- proto_pool()
any <- list(
  type_url = "type.googleapis.com/google.protobuf.Int32Value",
  value = proto_encode(42L, "google.protobuf.Int32Value", pool)
)
proto_unpack_any(any, pool)
#> [1] 42
```
