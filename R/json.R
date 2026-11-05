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
#' The entries of a map field, and so the keys of a `Struct`, are written
#' in no fixed order: it can differ between R sessions. With
#' `parse = TRUE` they are sorted by key, as [proto_decode()] sorts maps, so
#' the parsed value is the same in every session. Compare JSON as parsed
#' values, not as text.
#'
#' JSON meets R values through
#' [zujson](https://CRAN.R-project.org/package=zujson), which must be
#' installed for it. `proto_to_json(parse = TRUE)` returns
#' [zujson::json_parse()]'s R value. `proto_from_json()` takes an R value as
#' well as JSON text, and writes it with [zujson::json_write()]. There, a
#' length-1 vector is a JSON scalar, so give a repeated field of one element
#' as `I(x)` or `list(x)`.
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
  max_size = 64 * 1024^2,
  max_depth = 100L
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
    if (parse) {
      require_zujson("parse", sys.call())
    }
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
  if (!parse) {
    return(res$value)
  }
  json_sort_maps(
    zujson::json_parse(res$value),
    type,
    pool,
    bitwAnd(opts$json_options, 2L) != 0L
  )
}

# upb writes map entries, and so Struct keys, in hash order, which changes
# between sessions (#102). Patching its encoder is ruled out (design
# section 9.2), so the parsed value is sorted here, as proto_decode() sorts
# maps: by key, numerically for integer keys. The walk follows the schema,
# so message fields keep their order.
json_sort_maps <- function(x, type, pool, proto_names) {
  fields <- new.env(parent = emptyenv())
  type_fields <- function(type) {
    if (is.null(fields[[type]])) {
      f <- proto_fields(pool, type)
      f$key <- if (proto_names) f$name else f$json_name
      fields[[type]] <- f
    }
    fields[[type]]
  }
  walk_value <- function(v) {
    if (is.list(v) && !is.null(names(v))) {
      walk_struct(v)
    } else if (is.list(v)) {
      lapply(v, walk_value)
    } else {
      v
    }
  }
  walk_struct <- function(v) {
    lapply(v[order(names(v), method = "radix")], walk_value)
  }
  walk_any <- function(v) {
    url <- v[["@type"]]
    if (!is.character(url) || length(url) != 1L) {
      return(v)
    }
    inner <- sub("^.*/", "", url)
    if (inner %in% zpb_json_wkt) {
      if (!is.null(v[["value"]])) {
        v["value"] <- list(walk(v[["value"]], inner))
      }
      v
    } else {
      walk(v, inner)
    }
  }
  walk <- function(v, type) {
    switch(
      type,
      google.protobuf.Struct = if (is.list(v)) walk_struct(v) else v,
      google.protobuf.Value = walk_value(v),
      google.protobuf.ListValue = walk_value(v),
      google.protobuf.Any = if (is.list(v)) walk_any(v) else v,
      walk_message(v, type)
    )
  }
  walk_message <- function(v, type) {
    if (!is.list(v) || is.null(names(v)) || type %in% zpb_json_wkt) {
      return(v)
    }
    f <- type_fields(type)
    f <- f[f$type == "message" & f$key %in% names(v), , drop = FALSE]
    for (i in seq_len(nrow(f))) {
      key <- f$key[i]
      sub <- v[[key]]
      if (is.null(sub)) {
        next
      }
      sub <- if (f$map[i]) {
        walk_map(sub, f$type_name[i])
      } else if (f$label[i] == "repeated") {
        if (is.list(sub)) lapply(sub, walk, f$type_name[i]) else sub
      } else {
        walk(sub, f$type_name[i])
      }
      v[key] <- list(sub)
    }
    v
  }
  walk_map <- function(m, entry) {
    if (!is.list(m) || length(m) == 0L) {
      return(m)
    }
    e <- type_fields(entry)
    key_type <- e$type[e$number == 1L]
    m <- m[map_key_order(names(m), key_type)]
    val <- e[e$number == 2L, , drop = FALSE]
    if (val$type == "message") {
      m <- lapply(m, walk, val$type_name)
    }
    m
  }
  walk(x, type)
}

# The order of a map's JSON keys, for its key type.
map_key_order <- function(keys, key_type) {
  if (key_type %in% c("string", "bool")) {
    return(order(keys, method = "radix"))
  }
  # Integer keys, possibly 64-bit: sort by sign, then by magnitude as
  # digits padded to equal width, which is exact where doubles are not.
  neg <- startsWith(keys, "-")
  mag <- sub("^-", "", keys)
  mag <- paste0(strrep("0", max(nchar(mag)) - nchar(mag)), mag)
  rank <- integer(length(keys))
  rank[order(mag, method = "radix")] <- seq_along(keys)
  order(!neg, ifelse(neg, -rank, rank))
}

# The well-known types upb writes in a special JSON form, and so as the
# "value" member when packed in an Any.
zpb_json_wkt <- paste0(
  "google.protobuf.",
  c(
    "Any",
    "Struct",
    "Value",
    "ListValue",
    "Timestamp",
    "Duration",
    "FieldMask",
    "DoubleValue",
    "FloatValue",
    "Int64Value",
    "UInt64Value",
    "Int32Value",
    "UInt32Value",
    "BoolValue",
    "StringValue",
    "BytesValue"
  )
)

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
  enums <- zpb_match_arg(enums, zpb_choices$json_enums, "enums", call)
  check_limit(max_size, "max_size", 1, zpb_max_size_cap, call)
  check_limit(max_depth, "max_depth", 1, zpb_encode_max_depth, call)
  list(
    max_depth = as.integer(max_depth),
    json_options = as.integer(emit_defaults) +
      2L * as.integer(proto_names) +
      4L * as.integer(enums == "integer")
  )
}

# json_options() with every argument at its default, built once.
zpb_json_defaults <- list(
  max_depth = 100L,
  json_options = 0L
)

#' @rdname proto_to_json
#' @param json Protobuf JSON for one message: a single string of JSON text,
#'   or an R value to write as JSON with [zujson::json_write()].
#' @param ignore_unknown Whether to skip JSON fields the type does not
#'   define, rather than fail.
#' @inheritParams proto_encode
#' @export
proto_from_json <- function(
  json,
  type,
  pool,
  ignore_unknown = FALSE,
  check_required = TRUE,
  max_size = 64 * 1024^2
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
  if (Encoding(json) == "bytes") {
    zpb_invalid_argument(
      "json",
      "`json` must be text, not a string marked as bytes.",
      call
    )
  }
  check_flag(ignore_unknown, "ignore_unknown", call)
  check_flag(check_required, "check_required", call)
  check_limit(max_size, "max_size", 1, zpb_max_size_cap, call)
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
  res <- .Call(zpb_from_json, pool$ptr, type, json, opts)
  if (!is.null(res$error)) {
    # upb's JSON parser stops at 64 levels, below the encoder's 1000. If
    # that changes, the encoder's limit is raised as proto_encode() does.
    if (identical(res$error, "max_depth")) {
      encode_error(res, type, call)
    } else {
      json_error(res, type, max_size, NA, call)
    }
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

#' Pack and unpack an Any
#'
#' `proto_unpack_any()` decodes the message a `google.protobuf.Any` packs,
#' as [proto_decode()] decodes any message. The type is the part of
#' `type_url` after its last `/`, and must be in the pool.
#' `proto_pack_any()` is the inverse: it encodes a message with
#' [proto_encode()] and names its type, giving a value to set an `Any`
#' field to.
#'
#' @param x For `proto_unpack_any()`, an `Any` as [proto_decode()] returns
#'   it: a list of `type_url` and `value` (the packed bytes). For
#'   `proto_pack_any()`, the message, as [proto_encode()] takes it.
#' @param pool A pool from [proto_pool()] holding the packed type.
#' @param ... Passed to [proto_decode()] or [proto_encode()].
#' @return `proto_unpack_any()`: the packed message, as [proto_decode()]
#'   returns it. `proto_pack_any()`: an `Any`, a list of `type_url` and
#'   `value`.
#' @export
#' @examples
#' pool <- proto_pool()
#' any <- proto_pack_any(42L, "google.protobuf.Int32Value", pool)
#' any$type_url
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
  check_dots(...names(), ...length(), proto_decode, call)
  # Exact names: `$` would take `type_url_x` or `values` as well.
  type_url <- if (is.list(x)) x[["type_url", exact = TRUE]]
  value <- if (is.list(x)) x[["value", exact = TRUE]]
  ok <- is.character(type_url) &&
    length(type_url) == 1L &&
    !is.na(type_url) &&
    is.raw(value)
  if (!ok) {
    zpb_invalid_argument(
      "x",
      "`x` must be an Any: list(type_url = <string>, value = <raw>).",
      call
    )
  }
  type <- sub(".*/", "", type_url)
  if (!grepl("/", type_url, fixed = TRUE) || !nzchar(type)) {
    zpb_invalid_argument(
      "x",
      sprintf(
        "`x$type_url` ('%s') must name a type after its last /.",
        type_url
      ),
      call
    )
  }
  proto_decode(value, type, pool, ...)
}

#' @rdname proto_unpack_any
#' @param type The message type's full name.
#' @param prefix The `type_url` before the type name, ending in `/`.
#'   Protobuf's JSON mapping and most runtimes expect the default.
#' @export
proto_pack_any <- function(
  x,
  type,
  pool,
  prefix = "type.googleapis.com/",
  ...
) {
  call <- sys.call()
  ok <- is.character(prefix) &&
    length(prefix) == 1L &&
    !is.na(prefix) &&
    endsWith(prefix, "/")
  if (!ok) {
    zpb_invalid_argument(
      "prefix",
      "`prefix` must be a single string ending in /.",
      call
    )
  }
  check_dots(...names(), ...length(), proto_encode, call)
  value <- proto_encode(x, type, pool, ...)
  list(type_url = paste0(prefix, type), value = value)
}

require_zujson <- function(arg, call = NULL) {
  if (!has_namespace("zujson")) {
    zpb_invalid_argument(
      arg,
      "JSON as R values needs the zujson package. Install it, or give and take JSON text.",
      call
    )
  }
  invisible(TRUE)
}
