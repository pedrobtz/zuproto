# proto_decode(), design sections 5, 6 and 12. C decodes and builds;
# R checks arguments, reads input within max_size, and turns C's error
# codes and warning counts into classed conditions.

# Default limits, design section 5. zuproto_info() reports these.
zpb_limits <- list(max_size = 64 * 1024^2, max_depth = 100L)

# The most `max_depth` accepts, and the deepest nesting proto_encode()
# writes (ZPB_ENCODE_MAX_DEPTH in C counts the top-level message too).
zpb_encode_max_depth <- 1000L

# The choices of the decode arguments, built once rather than per call:
# argument handling is most of a small message's decode time.
zpb_choices <- list(
  int64 = c("double", "character", "integer64"),
  enums = c("factor", "integer", "character"),
  unknown = c("drop", "keep"),
  bytes = c("raw", "base64"),
  json_enums = c("name", "integer")
)

#' Decode one Protocol Buffers message
#'
#' Decodes the bytes of one message of type `type` into a named list, one
#' element per field, by the field's name. upb decodes the whole message
#' first; R values are built only from a message that decoded completely.
#'
#' @section Protobuf to R:
#' | Protobuf | R |
#' | --- | --- |
#' | `double`, `float` | double |
#' | `int32`, `sint32`, `sfixed32` | integer |
#' | `uint32`, `fixed32` | double, exact |
#' | `int64`, `uint64`, `sint64`, `fixed64`, `sfixed64` | per `int64` |
#' | `bool` | logical |
#' | `string` | character, UTF-8 |
#' | `bytes` | raw, or per `bytes` |
#' | enum | factor with the enum's value names as levels, or per `enums` |
#' | message | named list |
#' | `repeated` scalar | vector |
#' | `repeated` message | list of lists |
#' | `map<K, V>` | named vector or named list, sorted by key |
#' | `oneof` | the member that is set |
#' | extension | element named by its full name in brackets, `[pkg.ext]` |
#'
#' Well-known types: `Timestamp` becomes `POSIXct` in UTC, rounded to the
#' microsecond; `Duration` a `difftime` in seconds; a wrapper
#' (`Int32Value` and the rest) its value; `Struct` a named list, `Value`
#' its value (`NULL` for `null`) and `ListValue` a list, as in protobuf
#' JSON; `Any` a list of `type_url` and `value` (the packed bytes);
#' `FieldMask` a character vector of paths; `Empty` an empty list.
#' Repeated `Timestamp`, `Duration` and wrapper fields become vectors.
#'
#' A field that tracks presence (a message, a oneof member, a proto2 or
#' proto3 `optional` field) is left out when it is not set. A field that
#' does not track presence cannot be told apart from its default on the
#' wire; with `defaults = TRUE` it takes its default (`0`, `""`, `FALSE`,
#' the enum's first value, an empty vector), as other protobuf runtimes
#' do; with `defaults = FALSE` it is left out when it holds its default.
#'
#' Required fields are not checked: a proto2 `required` field missing
#' from the input decodes like any unset field.
#'
#' @param x The serialised message: a raw vector, a path to a file, or a
#'   connection. A file or connection is read up to `max_size` bytes.
#' @param type The message type's full name, such as `"pkg.Message"`.
#' @param pool A pool from [proto_pool()] holding `type`.
#' @param int64 How 64-bit integer fields become R values: `"double"`
#'   (values beyond 2^53 lose precision, with a `zuproto_precision_loss`
#'   warning), `"character"` (exact decimal strings) or `"integer64"`
#'   ([bit64::integer64()] vectors, exact for signed values; needs bit64).
#'   Under `"integer64"`, `-2^63` (bit64's `NA`) and `uint64` values above
#'   `2^63 - 1` become `NA` with a `zuproto_precision_loss` warning.
#' @param enums How enum fields become R values: `"factor"`, `"integer"`
#'   (the numbers) or `"character"` (the names). A number the enum does not
#'   define is `NA` with a `zuproto_unknown_enum` warning, except as an
#'   integer.
#' @param defaults Whether unset fields without presence take their
#'   defaults (`TRUE`) or are left out (`FALSE`).
#' @param unknown `"drop"` to discard fields the type does not define,
#'   `"keep"` to keep their bytes in an attribute `proto_unknown` on the
#'   message (and on each nested message) holding them.
#' @param bytes How `bytes` fields become R values: `"raw"` or `"base64"`
#'   (strings, as protobuf JSON writes them).
#' @param max_size The largest input accepted, in bytes. upb's memory for
#'   the decode is also capped. The cap is a multiple of the input's size,
#'   set by the message type: the most a message of that type could need.
#' @param max_depth The deepest nesting accepted: how many levels of
#'   messages within messages, the top-level message being level 0. A
#'   message holding a message holding a message is depth 2. A map entry
#'   counts as a level too, as upb counts it, so a message reached through
#'   a map is two levels down. At most 1000, so that hostile input cannot
#'   exhaust the C stack.
#' @return A named list. An `int32`-family value of `-2^31` is `NA`, with
#'   a `zuproto_precision_loss` warning, since R reserves it for `NA`.
#' @seealso [zuproto-conditions] for the errors it raises.
#' @export
#' @examples
#' pool <- proto_pool()
#' # A Timestamp of 1.5 seconds after the epoch: field 1 = 1, field 2 = 5e8.
#' bytes <- as.raw(c(0x08, 0x01, 0x10, 0x80, 0xca, 0xb5, 0xee, 0x01))
#' proto_decode(bytes, "google.protobuf.Timestamp", pool)
#' proto_decode(as.raw(c(0x08, 0x2a)), "google.protobuf.Int32Value", pool)
proto_decode <- function(
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
) {
  # A fast path, since argument handling was most of a small message's
  # decode time: arguments left at their defaults are not checked, and the
  # call is only captured when there is an error to raise.
  if (
    !inherits(pool, "proto_pool") ||
      !.Call(zpb_pool_is_valid, .subset2(pool, "ptr"))
  ) {
    check_pool(pool, call = sys.call())
  }
  if (
    !is.character(type) || length(type) != 1L || is.na(type) || !nzchar(type)
  ) {
    check_type(type, call = sys.call())
  }
  opts <- if (
    missing(int64) &&
      missing(enums) &&
      missing(defaults) &&
      missing(unknown) &&
      missing(bytes) &&
      missing(max_size) &&
      missing(max_depth)
  ) {
    zpb_decode_defaults
  } else {
    decode_options(
      int64,
      enums,
      defaults,
      unknown,
      bytes,
      max_size,
      max_depth,
      sys.call()
    )
  }
  raw <- if (is.raw(x) && length(x) <= max_size) {
    x
  } else {
    read_message(x, max_size, sys.call())
  }

  res <- .Call(zpb_decode, .subset2(pool, "ptr"), type, raw, opts)
  if (!is.null(res$error)) {
    decode_error(res, type, max_size, max_depth, sys.call())
  }
  if (res$precision_loss > 0 || res$unknown_enum > 0) {
    decode_warnings(res, type, sys.call())
  }
  res$value
}

# The checked options list for zpb_decode(), as proto_decode() builds it when
# any argument is not its default.
decode_options <- function(
  int64,
  enums,
  defaults,
  unknown,
  bytes,
  max_size,
  max_depth,
  call
) {
  int64 <- zpb_match_arg(int64, zpb_choices$int64, "int64", call)
  check_int64_mode(int64, call)
  enums <- zpb_match_arg(enums, zpb_choices$enums, "enums", call)
  unknown <- zpb_match_arg(unknown, zpb_choices$unknown, "unknown", call)
  bytes <- zpb_match_arg(bytes, zpb_choices$bytes, "bytes", call)
  check_flag(defaults, "defaults", call)
  check_limit(max_size, "max_size", 1, 2^53, call)
  # upb's decoder recurses once per level; 1000 stays far below the depth
  # (about 5000) at which the C stack ran out on an 8 MB stack.
  check_limit(max_depth, "max_depth", 1, zpb_encode_max_depth, call)
  list(
    int64 = match(int64, zpb_choices$int64) - 1L,
    enums = match(enums, zpb_choices$enums) - 1L,
    defaults = as.integer(defaults),
    keep_unknown = as.integer(unknown == "keep"),
    bytes_base64 = as.integer(bytes == "base64"),
    max_depth = as.integer(max_depth)
  )
}

# decode_options() with every argument at its default, built once.
zpb_decode_defaults <- list(
  int64 = 0L,
  enums = 0L,
  defaults = 1L,
  keep_unknown = 0L,
  bytes_base64 = 0L,
  max_depth = zpb_limits$max_depth
)

decode_error <- function(res, type, max_size, max_depth, call) {
  switch(
    res$error,
    unknown_type = zpb_abort(
      "zuproto_unknown_type",
      sprintf("Message type '%s' is not in the pool.", type),
      type = type,
      call = call
    ),
    malformed = ,
    other = zpb_abort(
      "zuproto_parse_error",
      sprintf(
        "Cannot decode the input as '%s': the bytes are not a valid message of that type.",
        type
      ),
      status = res$error,
      call = call
    ),
    invalid_utf8 = zpb_abort(
      c("zuproto_invalid_utf8", "zuproto_parse_error"),
      sprintf(
        "Cannot decode the input as '%s': a string field is not valid UTF-8.",
        type
      ),
      status = res$error,
      call = call
    ),
    max_depth = zpb_abort(
      c("zuproto_depth_limit", "zuproto_limit_error"),
      sprintf(
        "Cannot decode the input as '%s': messages are nested deeper than `max_depth` (%d).",
        type,
        as.integer(max_depth)
      ),
      limit = "max_depth",
      limit_value = max_depth,
      call = call
    ),
    arena_limit = zpb_abort(
      c("zuproto_size_limit", "zuproto_limit_error"),
      sprintf(
        "Cannot decode the input as '%s': it needs more memory than a message of that type and size can legitimately need.",
        type
      ),
      # No argument sets this ceiling, so a larger `max_size` would not help.
      limit = "memory",
      limit_value = NA_real_,
      call = call
    ),
    nul_in_string = ,
    string_too_long = zpb_abort(
      "zuproto_unrepresentable",
      sprintf(
        "Cannot decode the input as '%s': field '%s' holds a string R cannot, %s.",
        type,
        res$field,
        if (res$error == "nul_in_string") {
          "one containing a NUL byte"
        } else {
          "one longer than 2^31 - 1 bytes"
        }
      ),
      field = res$field,
      call = call
    ),
    abort_internal(
      res$error,
      sprintf("decode the input as '%s'", type),
      call
    )
  )
}

decode_warnings <- function(res, type, call) {
  if (res$precision_loss > 0) {
    zpb_warn(
      "zuproto_precision_loss",
      sprintf(
        "%s in '%s' could not be represented exactly: 64-bit integers beyond 2^53 were rounded, and 32-bit -2^31 became NA. Use `int64 = \"character\"` for exact 64-bit values.",
        plural(res$precision_loss, "value"),
        type
      ),
      n = res$precision_loss,
      call = call
    )
  }
  if (res$unknown_enum > 0) {
    zpb_warn(
      "zuproto_unknown_enum",
      sprintf(
        "%s in '%s' named no value of its enum and became NA.",
        plural(res$unknown_enum, "enum value"),
        type
      ),
      n = res$unknown_enum,
      call = call
    )
  }
}

plural <- function(n, what) {
  sprintf(
    "%s %s%s",
    format(n, scientific = FALSE),
    what,
    if (n == 1) "" else "s"
  )
}

# Input for one message, refused beyond max_size before upb sees it.
read_message <- function(x, max_size, call) {
  abort_too_big <- function(n) {
    zpb_abort(
      c("zuproto_size_limit", "zuproto_limit_error"),
      sprintf(
        "The input is larger than `max_size` (%s bytes).",
        format(max_size, scientific = FALSE)
      ),
      limit = "max_size",
      limit_value = max_size,
      size = n,
      call = call
    )
  }
  if (is.raw(x)) {
    if (length(x) > max_size) {
      abort_too_big(length(x))
    }
    return(x)
  }
  if (
    is.character(x) &&
      length(x) == 1L &&
      !is.na(x) &&
      file.exists(x) &&
      !dir.exists(x)
  ) {
    size <- file.size(x)
    if (size > max_size) {
      abort_too_big(size)
    }
  }
  raw <- read_input(x, "x", call, limit = max_size + 1)
  if (length(raw) > max_size) {
    abort_too_big(NA_real_)
  }
  raw
}
