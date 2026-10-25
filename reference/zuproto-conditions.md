# Conditions raised by zuproto

Every error zuproto raises carries a condition class, so it can be
caught by kind rather than by matching the message, which may change.
Every class below inherits from `zuproto_error`.

## Details

- `zuproto_invalid_argument`:

  An argument was unusable, such as a pool that is not one, or a type
  name that is not a single string. Carries `arg`, the argument at
  fault.

- `zuproto_io_error`:

  A file could not be opened or read, or a connection could not be read
  from.

- `zuproto_pool_error`:

  A descriptor set could not be added to a pool: the bytes are not a
  `FileDescriptorSet`, a file imports one that is neither in the set nor
  in the pool, or upb rejected a file. Carries `file`, the file at
  fault, when there is one.

- `zuproto_pool_conflict`:

  A subclass of `zuproto_pool_error`: a file of the same name is already
  in the pool, or earlier in the set, with different contents. Carries
  `file`.

- `zuproto_unknown_type`:

  A message type is not in the pool. Carries `type`.

- `zuproto_parse_error`:

  The input is not a valid message of the type: it ends early, has a bad
  tag, a length beyond the input, or the wrong wire type. Carries
  `status`.

- `zuproto_invalid_utf8`:

  A subclass of `zuproto_parse_error`: a `string` field is not valid
  UTF-8, in proto2 as in proto3.

- `zuproto_unrepresentable`:

  The input is valid but holds a value R cannot: a string containing a
  NUL byte, or longer than an R string may be. Carries `field`, the
  field's full name.

- `zuproto_limit_error`:

  A limit was reached. The subclasses `zuproto_size_limit` (the input,
  or the memory decoding it needs, is too large for `max_size`) and
  `zuproto_depth_limit` (messages nest deeper than `max_depth`) name
  which. Carries `limit`, the argument's name, and `limit_value`.

Warnings inherit `zuproto_warning`:

- `zuproto_precision_loss`:

  Values could not be represented exactly: 64-bit integers beyond 2^53
  decoded as doubles, or a 32-bit `-2^31`, which R reserves for `NA`.
  Carries `n`, how many.

- `zuproto_unknown_enum`:

  Enum numbers the enum does not define became `NA`. Carries `n`.

## Examples

``` r
pool <- proto_pool()
tryCatch(
  proto_fields(pool, "no.such.Message"),
  zuproto_unknown_type = function(e) e$type
)
#> [1] "no.such.Message"
```
