# Length-delimited streams

`proto_read_delimited()` reads a stream of messages, each preceded by
its length as a varint, as Java's `writeDelimitedTo()`, Python's
`_VarintBytes` helpers and many `.pb` log files write them, into a data
frame like
[`proto_decode_df()`](https://pedrobtz.github.io/zuproto/reference/proto_decode_df.md)
builds. With `each`, it reads the stream in chunks of `chunk_rows`
messages and calls `each(df)` on each chunk instead, so a stream larger
than memory can be processed. `proto_write_delimited()` writes one.

## Usage

``` r
proto_read_delimited(
  x,
  type,
  pool,
  each = NULL,
  chunk_rows = 10000,
  int64 = c("double", "character", "integer64"),
  enums = c("factor", "integer", "character"),
  defaults = TRUE,
  bytes = c("raw", "base64"),
  max_size = zpb_limits$max_size,
  max_depth = zpb_limits$max_depth,
  max_rows = 1e+07
)

proto_write_delimited(x, type, pool, path = NULL, ...)
```

## Arguments

- x:

  For
  [`proto_decode_df()`](https://pedrobtz.github.io/zuproto/reference/proto_decode_df.md),
  a list of raw vectors, one message each; with `field`, one message as
  a raw vector, a path or a connection. For `proto_read_delimited()`, a
  raw vector, a path or a connection holding a length-delimited stream.

- type:

  The message type's full name, such as `"pkg.Message"`.

- pool:

  A pool from
  [`proto_pool()`](https://pedrobtz.github.io/zuproto/reference/proto_pool.md)
  holding `type`.

- each:

  `NULL`, or a function called with each chunk's data frame.

- chunk_rows:

  The number of messages in each chunk given to `each`.

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

- bytes:

  How `bytes` fields become R values: `"raw"` or `"base64"` (strings, as
  protobuf JSON writes them).

- max_size:

  The largest input accepted, in bytes. upb's memory for the decode is
  also capped. The cap is a multiple of the input's size, set by the
  message type: the most a message of that type could need.

- max_depth:

  The deepest nesting accepted: how many levels of messages within
  messages, the top-level message being level 0. A message holding a
  message holding a message is depth 2. A map entry counts as a level
  too, as upb counts it, so a message reached through a map is two
  levels down. At most 1000, so that hostile input cannot exhaust the C
  stack.

- max_rows:

  The largest number of rows accepted. With `each`, it bounds each
  chunk, not the whole stream, which is read a chunk at a time and never
  held whole.

- path:

  `NULL` to return the stream, or a path to write it to.

- ...:

  Passed to
  [`proto_encode()`](https://pedrobtz.github.io/zuproto/reference/proto_encode.md)
  for each message.

## Value

`proto_read_delimited()`: a data frame, or with `each`, `NULL`,
invisibly.

`proto_write_delimited()`: the stream as a raw vector, or with `path`,
the path, invisibly.

## Details

A stream that ends inside a length or a message is a
`zuproto_parse_error`.

`proto_write_delimited()` takes a data frame whose columns follow the
column table of
[`proto_decode_df()`](https://pedrobtz.github.io/zuproto/reference/proto_decode_df.md),
one message per row, or a list of messages as
[`proto_encode()`](https://pedrobtz.github.io/zuproto/reference/proto_encode.md)
takes them. `NA` values leave fields unset, and `<oneof>_case` columns
are ignored.

## Examples

``` r
pool <- proto_pool()
rows <- data.frame(seconds = c(1, 2, 3), nanos = 0L)
stream <- proto_write_delimited(rows, "google.protobuf.Duration", pool)
proto_read_delimited(stream, "google.protobuf.Duration", pool)
#>   seconds nanos
#> 1       1     0
#> 2       2     0
#> 3       3     0
```
