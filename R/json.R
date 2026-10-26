# Protobuf JSON and Any, design sections 5 and 6.3. upb converts between
# binary and JSON; R checks arguments and raises.

#' Protobuf JSON
#'
#' Converts a binary message to protobuf's canonical JSON mapping and back,
#' through upb. JSON field names are the `json_name`s (lowerCamelCase) by
#' default, 64-bit integers are strings, bytes are base64, and well-known
#' types take their special JSON forms (`Timestamp` as an RFC 3339 string,
#' `Struct` as an object, and so on).
#'
#' `Any` messages convert only when the type they pack is in the pool.
#'
#' JSON meets R values through [zujson](https://CRAN.R-project.org/package=zujson),
#' which must be installed for it: `proto_to_json(parse = TRUE)` returns
#' [zujson::json_parse()]'s R value, and `proto_from_json()` takes an R value
#' as well as JSON text, written with [zujson::json_write()]. There, a
#' length-1 vector is a JSON scalar: give a repeated field of one element as
#' `I(x)` or `list(x)`.
#'
#' @inheritParams proto_decode
#' @param x For `proto_to_json()`, the binary message: a raw vector, a path
#'   or a connection.
#' @param emit_defaults Whether to write fields that hold their defaults.
#' @param proto_names Whether to use the `.proto` field names rather than
#'   their `json_name`s.
#' @param enums `"name"` or `"integer"`: how enum values are written.
#' @param parse Whether to return the JSON parsed into an R value by
#'   [zujson::json_parse()] rather than as text.
#' @return `proto_to_json()`: a single string, or with `parse = TRUE` an R
#'   value. `proto_from_json()`: the message as a raw vector, encoded
#'   deterministically.
#' @export
#' @examples
#' pool <- proto_pool()
#' raw <- proto_encode(
#'   as.POSIXct("2026-10-25 12:00:00", tz = "UTC"),
#'   "google.protobuf.Timestamp", pool
#' )
#' json <- proto_to_json(raw, "google.protobuf.Timestamp", pool)
#' json
#' identical(proto_from_json(json, "google.protobuf.Timestamp", pool), raw)
proto_to_json <- function(
  x,
  type,
  pool,
  emit_defaults = FALSE,
  proto_names = FALSE,
  enums = c("name", "integer"),
  parse = FALSE,
  max_size = zpb_limits$max_size,
  max_depth = zpb_limits$max_depth
) {
  # A fast path, as in proto_decode().
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
  if (!missing(parse)) {
    check_flag(parse, "parse", sys.call())
    if (parse) require_zujson("parse", sys.call())
  }
  opts <- if (
    missing(emit_defaults) &&
      missing(proto_names) &&
      missing(enums) &&
      missing(max_size) &&
      missing(max_depth)
  ) {
    zpb_json_defaults
  } else {
    json_options(
      emit_defaults,
      proto_names,
      enums,
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
  res <- .Call(zpb_to_json, .subset2(pool, "ptr"), type, raw, opts)
  if (!is.null(res$error)) {
    json_error(res, type, max_size, max_depth, sys.call())
  }
  if (parse) zujson::json_parse(res$value) else res$value
}

# The checked options list for zpb_to_json().
json_options <- function(
  emit_defaults,
  proto_names,
  enums,
  max_size,
  max_depth,
  call
) {
  check_flag(emit_defaults, "emit_defaults", call)
  check_flag(proto_names, "proto_names", call)
  enums <- zpb_match_arg(enums, c("name", "integer"), "enums", call)
  check_limit(max_size, "max_size", 1, 2^53, call)
  check_limit(max_depth, "max_depth", 1, 1000, call)
  list(
    max_depth = as.integer(max_depth),
    json_options = as.integer(emit_defaults) +
      2L * as.integer(proto_names) +
      4L * as.integer(enums == "integer")
  )
}

# json_options() with every argument at its default, built once.
zpb_json_defaults <- list(
  max_depth = zpb_limits$max_depth,
  json_options = 0L
)

#' @rdname proto_to_json
#' @param json Protobuf JSON for one message: a single string of JSON text,
#'   or an R value to write as JSON with [zujson::json_write()].
#' @param ignore_unknown Whether to skip JSON fields the type does not
#'   define, rather than fail.
#' @param check_required Whether a missing proto2 `required` field is an
#'   error.
#' @export
proto_from_json <- function(
  json,
  type,
  pool,
  ignore_unknown = FALSE,
  check_required = TRUE,
  max_size = zpb_limits$max_size
) {
  call <- sys.call()
  check_pool(pool, call = call)
  check_type(type, call = call)
  if (!(is.character(json) && length(json) == 1L)) {
    require_zujson("json", call)
    json <- zujson::json_write(json, auto_unbox = TRUE)
  }
  if (is.na(json)) {
    zpb_invalid_argument(
      "json",
      "`json` must be JSON text or an R value, not NA.",
      call
    )
  }
  check_flag(ignore_unknown, "ignore_unknown", call)
  check_flag(check_required, "check_required", call)
  check_limit(max_size, "max_size", 1, 2^53, call)
  size <- nchar(json, type = "bytes")
  if (size > max_size) {
    zpb_abort(
      c("zuproto_size_limit", "zuproto_limit_error"),
      sprintf(
        "The JSON is larger than `max_size` (%s bytes).",
        format(max_size, scientific = FALSE)
      ),
      limit = "max_size",
      limit_value = max_size,
      call = call
    )
  }
  opts <- list(
    ignore_unknown = as.integer(ignore_unknown),
    check_required = as.integer(check_required)
  )
  res <- .Call(zpb_from_json, pool$ptr, type, enc2utf8(json), opts)
  if (!is.null(res$error)) {
    # upb's JSON parser stops at 64 levels (a zuproto_json_error), so the
    # encoder's limit of 1000 is not reached from JSON; were it, it is the
    # encoder's error, as proto_encode() raises it.
    if (identical(res$error, "max_depth")) {
      encode_error(res, type, call)
    }
    json_error(res, type, max_size, NA, call)
  }
  res$value
}

json_error <- function(res, type, max_size, max_depth, call) {
  switch(
    res$error,
    json = zpb_abort(
      "zuproto_json_error",
      sprintf("Cannot convert '%s' to or from JSON: %s.", type, res$detail),
      detail = res$detail,
      call = call
    ),
    missing_required = zpb_abort(
      "zuproto_missing_required",
      sprintf(
        "Cannot encode the JSON as '%s': a required field is not set.",
        type
      ),
      call = call
    ),
    decode_error(res, type, max_size, max_depth, call)
  )
}

#' Unpack an Any
#'
#' Decodes the message a `google.protobuf.Any` packs, as [proto_decode()]
#' decodes any message. The type is the part of `type_url` after its last
#' `/`, and must be in the pool.
#'
#' @param x An `Any` as [proto_decode()] returns it: a list of `type_url`
#'   and `value` (the packed bytes).
#' @param pool A pool from [proto_pool()] holding the packed type.
#' @param ... Passed to [proto_decode()].
#' @return The packed message, as [proto_decode()] returns it.
#' @export
#' @examples
#' pool <- proto_pool()
#' any <- list(
#'   type_url = "type.googleapis.com/google.protobuf.Int32Value",
#'   value = proto_encode(42L, "google.protobuf.Int32Value", pool)
#' )
#' proto_unpack_any(any, pool)
proto_unpack_any <- function(x, pool, ...) {
  call <- sys.call()
  if ("type" %in% ...names()) {
    zpb_invalid_argument(
      "type",
      "`type` comes from `x$type_url`; it cannot be given.",
      call
    )
  }
  ok <- is.list(x) &&
    is.character(x$type_url) &&
    length(x$type_url) == 1L &&
    !is.na(x$type_url) &&
    is.raw(x$value)
  if (!ok) {
    zpb_invalid_argument(
      "x",
      "`x` must be an Any: list(type_url = <string>, value = <raw>).",
      call
    )
  }
  type <- sub(".*/", "", x$type_url)
  if (!nzchar(type)) {
    zpb_invalid_argument(
      "x",
      sprintf("`x$type_url` ('%s') names no type.", x$type_url),
      call
    )
  }
  proto_decode(x$value, type, pool, ...)
}

require_zujson <- function(arg, call = NULL) {
  if (!requireNamespace("zujson", quietly = TRUE)) {
    zpb_invalid_argument(
      arg,
      "JSON as R values needs the zujson package. Install it, or give and take JSON text.",
      call
    )
  }
  invisible(TRUE)
}
