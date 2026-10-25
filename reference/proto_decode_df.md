# Decode many messages into a data frame

Decodes many messages of one type into a data frame, one row per
message, built column by column: every message is decoded first, then
each column is filled across all of them. A message that fails stops the
whole call, and the condition's `index` says which one.

## Usage

``` r
proto_decode_df(
  x,
  type,
  pool,
  field = NULL,
  int64 = c("double", "character"),
  enums = c("factor", "integer", "character"),
  defaults = TRUE,
  bytes = c("raw", "base64"),
  max_size = zpb_default_limits()$max_size,
  max_depth = zpb_default_limits()$max_depth,
  max_rows = 1e+07
)
```

## Arguments

- x:

  For `proto_decode_df()`, a list of raw vectors, one message each; with
  `field`, one message as a raw vector, a path or a connection. For
  [`proto_read_delimited()`](https://pedrobtz.github.io/zuproto/reference/proto_read_delimited.md),
  a raw vector, a path or a connection holding a length-delimited
  stream.

- type:

  The message type's full name, such as `"pkg.Message"`.

- pool:

  A pool from
  [`proto_pool()`](https://pedrobtz.github.io/zuproto/reference/proto_pool.md)
  holding `type`.

- field:

  The name of a repeated message field of `type`, or `NULL`.

- int64:

  How 64-bit integer fields become R values: `"double"` (values beyond
  2^53 lose precision, with a `zuproto_precision_loss` warning) or
  `"character"` (exact decimal strings).

- enums:

  How enum fields become R values: `"factor"`, `"integer"` (the numbers)
  or `"character"` (the names). A number the enum does not define is
  `NA` with a `zuproto_unknown_enum` warning, except as an integer.

- defaults:

  Whether unset fields without presence take their defaults (`TRUE`) or
  are left out (`FALSE`).

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

- max_rows:

  The largest number of rows accepted.

## Value

A data frame.

## Details

With `field`, the input is one message instead, and the rows are the
elements of its repeated message field `field`. That is how feeds that
wrap their records in one message become tables, a GTFS Realtime
`FeedMessage` and its `entity` field for one.

## Columns

|  |  |
|----|----|
| Field | Column |
| scalar, enum, scalar-like well-known type | atomic vector, as in [`proto_decode()`](https://pedrobtz.github.io/zuproto/reference/proto_decode.md) |
| `bytes` | list of raw vectors |
| message | data frame (a column of the frame) |
| `repeated` scalar | list of vectors |
| `repeated` message | list of data frames |
| `map` | list of named vectors or lists |
| `Struct`, `Value`, `ListValue`, `Any` | list, as in [`proto_decode()`](https://pedrobtz.github.io/zuproto/reference/proto_decode.md) |
| `oneof` | a column per member, plus `<oneof>_case` with the member set |
| extension | a column named `[pkg.ext]` per extension the pool knows |

A field a row does not set is `NA` (`NULL` in a list column) when the
field tracks presence; otherwise it takes its default, or is `NA` with
`defaults = FALSE`. A message field that no row sets is an all-`NA`
logical column rather than a data frame, which is also where the columns
of a recursive type end. A message type with no fields, such as `Empty`,
is a list column: [`list()`](https://rdrr.io/r/base/list.html) where
set, `NULL` where not. A nested message that is set but has every field
unset reads as unset, since its row is all `NA`.

## See also

[`proto_read_delimited()`](https://pedrobtz.github.io/zuproto/reference/proto_read_delimited.md)
for length-delimited streams.

## Examples

``` r
pool <- proto_pool()
# Three FieldDescriptorProto messages, one per row.
msgs <- lapply(c("id", "name", "when"), function(name) {
  proto_encode(list(name = name, number = 1L), "google.protobuf.FieldDescriptorProto", pool)
})
df <- proto_decode_df(msgs, "google.protobuf.FieldDescriptorProto", pool)
df[c("name", "number")]
#>   name number
#> 1   id      1
#> 2 name      1
#> 3 when      1
```
