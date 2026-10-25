# Protobuf JSON

Converts a binary message to protobuf's canonical JSON mapping and back,
through upb. JSON field names are the `json_name`s (lowerCamelCase) by
default, 64-bit integers are strings, bytes are base64, and well-known
types take their special JSON forms (`Timestamp` as an RFC 3339 string,
`Struct` as an object, and so on).

## Usage

``` r
proto_to_json(
  x,
  type,
  pool,
  emit_defaults = FALSE,
  proto_names = FALSE,
  enums = c("name", "integer"),
  parse = FALSE,
  max_size = zpb_limits$max_size,
  max_depth = zpb_limits$max_depth
)

proto_from_json(
  json,
  type,
  pool,
  ignore_unknown = FALSE,
  check_required = TRUE,
  max_size = zpb_limits$max_size
)
```

## Arguments

- x:

  For `proto_to_json()`, the binary message: a raw vector, a path or a
  connection.

- type:

  The message type's full name, such as `"pkg.Message"`.

- pool:

  A pool from
  [`proto_pool()`](https://pedrobtz.github.io/zuproto/reference/proto_pool.md)
  holding `type`.

- emit_defaults:

  Whether to write fields that hold their defaults.

- proto_names:

  Whether to use the `.proto` field names rather than their
  `json_name`s.

- enums:

  `"name"` or `"integer"`: how enum values are written.

- parse:

  Whether to return the JSON parsed into an R value by
  [`zujson::json_parse()`](https://pedrobtz.github.io/zujson/reference/json_parse.html)
  rather than as text.

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

- json:

  Protobuf JSON for one message: a single string of JSON text, or an R
  value to write as JSON with
  [`zujson::json_write()`](https://pedrobtz.github.io/zujson/reference/json_write.html).

- ignore_unknown:

  Whether to skip JSON fields the type does not define, rather than
  fail.

- check_required:

  Whether a missing proto2 `required` field is an error.

## Value

`proto_to_json()`: a single string, or with `parse = TRUE` an R value.
`proto_from_json()`: the message as a raw vector, encoded
deterministically.

## Details

`Any` messages convert only when the type they pack is in the pool.

JSON meets R values through
[zujson](https://CRAN.R-project.org/package=zujson), which must be
installed for it: `proto_to_json(parse = TRUE)` returns
[`zujson::json_parse()`](https://pedrobtz.github.io/zujson/reference/json_parse.html)'s
R value, and `proto_from_json()` takes an R value as well as JSON text,
written with
[`zujson::json_write()`](https://pedrobtz.github.io/zujson/reference/json_write.html).
There, a length-1 vector is a JSON scalar: give a repeated field of one
element as `I(x)` or `list(x)`.

## Examples

``` r
pool <- proto_pool()
raw <- proto_encode(
  as.POSIXct("2026-10-25 12:00:00", tz = "UTC"),
  "google.protobuf.Timestamp", pool
)
json <- proto_to_json(raw, "google.protobuf.Timestamp", pool)
json
#> [1] "\"2026-10-25T12:00:00Z\""
identical(proto_from_json(json, "google.protobuf.Timestamp", pool), raw)
#> [1] TRUE
```
