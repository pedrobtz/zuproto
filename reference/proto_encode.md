# Encode one Protocol Buffers message

Encodes a named list as one message of type `type`, the inverse of
[`proto_decode()`](https://pedrobtz.github.io/zuproto/reference/proto_decode.md):
every value
[`proto_decode()`](https://pedrobtz.github.io/zuproto/reference/proto_decode.md)
returns encodes back to the same message.

## Usage

``` r
proto_encode(
  x,
  type,
  pool,
  deterministic = TRUE,
  unknown = TRUE,
  check_required = TRUE,
  extra = c("error", "ignore")
)
```

## Arguments

- x:

  A named list, one element per field. For a well-known type with an R
  scalar form (`Timestamp`, `Duration`, wrappers), that scalar.

- type:

  The message type's full name, such as `"pkg.Message"`.

- pool:

  A pool from
  [`proto_pool()`](https://pedrobtz.github.io/zuproto/reference/proto_pool.md)
  holding `type`.

- deterministic:

  Whether to encode deterministically: map entries sorted by key, so
  equal values always give equal bytes.

- unknown:

  Whether to write back unknown fields kept by
  `proto_decode(unknown = "keep")` in a `proto_unknown` attribute.

- check_required:

  Whether a missing proto2 `required` field is an error.

- extra:

  `"error"` to refuse names the type does not define, `"ignore"` to skip
  them.

## Value

A raw vector.

## Details

Each element is a field, by its name, or an extension, by its full name
in brackets (`"[pkg.ext]"`). An element that is `NULL` or `NA` leaves
its field unset, as does a field the list leaves out. Values take the R
forms
[`proto_decode()`](https://pedrobtz.github.io/zuproto/reference/proto_decode.md)
gives them, and also:

- integer kinds: integers, or doubles that are whole and in range;
  64-bit kinds also decimal strings, which are exact;

- enums: factors, value names, or numbers (a closed enum accepts only
  the numbers it defines);

- `Timestamp`: `POSIXct` or seconds since the epoch; `Duration`:
  `difftime` or seconds; a wrapper: its value;

- `Value`: `NULL`, a logical, number or string, a named list (a
  `Struct`), or an unnamed list or vector (a `ListValue`).

`bytes` fields take raw vectors (a list of them when repeated).

## See also

[zuproto-conditions](https://pedrobtz.github.io/zuproto/reference/zuproto-conditions.md)
for the errors it raises; each one about a value carries `path`, the
field at fault, such as `"points[2].x"`.

## Examples

``` r
pool <- proto_pool()
proto_encode(42L, "google.protobuf.Int32Value", pool)
#> [1] 08 2a
when <- as.POSIXct("2026-10-25 12:00:00", tz = "UTC")
raw <- proto_encode(when, "google.protobuf.Timestamp", pool)
proto_decode(raw, "google.protobuf.Timestamp", pool)
#> [1] "2026-10-25 12:00:00 UTC"
```
