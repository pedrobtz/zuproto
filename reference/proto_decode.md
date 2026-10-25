# Decode one Protocol Buffers message

Decodes the bytes of one message of type `type` into a named list, one
element per field, by the field's name. upb decodes the whole message
first; R values are built only from a message that decoded completely.

## Usage

``` r
proto_decode(
  x,
  type,
  pool,
  int64 = c("double", "character", "integer64"),
  enums = c("factor", "integer", "character"),
  defaults = TRUE,
  unknown = c("drop", "keep"),
  bytes = c("raw", "base64"),
  max_size = zpb_limits$max_size,
  max_depth = zpb_limits$max_depth
)
```

## Arguments

- x:

  The serialised message: a raw vector, a path to a file, or a
  connection. A file or connection is read up to `max_size` bytes.

- type:

  The message type's full name, such as `"pkg.Message"`.

- pool:

  A pool from
  [`proto_pool()`](https://pedrobtz.github.io/zuproto/reference/proto_pool.md)
  holding `type`.

- int64:

  How 64-bit integer fields become R values: `"double"` (values beyond
  2^53 lose precision, with a `zuproto_precision_loss` warning),
  `"character"` (exact decimal strings) or `"integer64"`
  ([`bit64::integer64()`](https://bit64.r-lib.org/reference/bit64-package.html)
  vectors, exact for signed values; needs bit64). Under `"integer64"`,
  `-2^63` (bit64's `NA`) and `uint64` values above `2^63 - 1` become
  `NA` with a `zuproto_precision_loss` warning.

- enums:

  How enum fields become R values: `"factor"`, `"integer"` (the numbers)
  or `"character"` (the names). A number the enum does not define is
  `NA` with a `zuproto_unknown_enum` warning, except as an integer.

- defaults:

  Whether unset fields without presence take their defaults (`TRUE`) or
  are left out (`FALSE`).

- unknown:

  `"drop"` to discard fields the type does not define, `"keep"` to keep
  their bytes in an attribute `proto_unknown` on the message (and on
  each nested message) holding them.

- bytes:

  How `bytes` fields become R values: `"raw"` or `"base64"` (strings, as
  protobuf JSON writes them).

- max_size:

  The largest input accepted, in bytes. upb's memory for the decode is
  capped at four times this.

- max_depth:

  The deepest nesting accepted: how many levels of messages within
  messages, the top-level message being level 0. A message holding a
  message holding a message is depth 2. A map entry counts as a level
  too, as upb counts it, so a message reached through a map is two
  levels down. At most 1000, so that hostile input cannot exhaust the C
  stack.

## Value

A named list. An `int32`-family value of `-2^31` is `NA`, with a
`zuproto_precision_loss` warning, since R reserves it for `NA`.

## Protobuf to R

|  |  |
|----|----|
| Protobuf | R |
| `double`, `float` | double |
| `int32`, `sint32`, `sfixed32` | integer |
| `uint32`, `fixed32` | double, exact |
| `int64`, `uint64`, `sint64`, `fixed64`, `sfixed64` | per `int64` |
| `bool` | logical |
| `string` | character, UTF-8 |
| `bytes` | raw, or per `bytes` |
| enum | factor with the enum's value names as levels, or per `enums` |
| message | named list |
| `repeated` scalar | vector |
| `repeated` message | list of lists |
| `map<K, V>` | named vector or named list, sorted by key |
| `oneof` | the member that is set |
| extension | element named by its full name in brackets, `[pkg.ext]` |

Well-known types: `Timestamp` becomes `POSIXct` in UTC, rounded to the
microsecond; `Duration` a `difftime` in seconds; a wrapper (`Int32Value`
and the rest) its value; `Struct` a named list, `Value` its value
(`NULL` for `null`) and `ListValue` a list, as in protobuf JSON; `Any` a
list of `type_url` and `value` (the packed bytes); `FieldMask` a
character vector of paths; `Empty` an empty list. Repeated `Timestamp`,
`Duration` and wrapper fields become vectors.

A field that tracks presence (a message, a oneof member, a proto2 or
proto3 `optional` field) is left out when it is not set. A field that
does not track presence cannot be told apart from its default on the
wire; with `defaults = TRUE` it takes its default (`0`, `""`, `FALSE`,
the enum's first value, an empty vector), as other protobuf runtimes do;
with `defaults = FALSE` it is left out when it holds its default.

Required fields are not checked: a proto2 `required` field missing from
the input decodes like any unset field.

## See also

[zuproto-conditions](https://pedrobtz.github.io/zuproto/reference/zuproto-conditions.md)
for the errors it raises.

## Examples

``` r
pool <- proto_pool()
# A Timestamp of 1.5 seconds after the epoch: field 1 = 1, field 2 = 5e8.
bytes <- as.raw(c(0x08, 0x01, 0x10, 0x80, 0xca, 0xb5, 0xee, 0x01))
proto_decode(bytes, "google.protobuf.Timestamp", pool)
#> [1] "1970-01-01 00:00:01 UTC"
proto_decode(as.raw(c(0x08, 0x2a)), "google.protobuf.Int32Value", pool)
#> [1] 42
```
