# proto_encode(), design sections 5 and 7. C walks the value against the
# message definition and encodes; R checks arguments and raises.

#' Encode one Protocol Buffers message
#'
#' Encodes a named list as one message of type `type`, the inverse of
#' [proto_decode()]: every value `proto_decode()` returns encodes back to
#' the same message.
#'
#' Each element is a field, by its name, or an extension, by its full name
#' in brackets (`"[pkg.ext]"`). An element that is `NULL` or `NA` leaves its
#' field unset, as does a field the list leaves out. Values take the R
#' forms `proto_decode()` gives them, and also:
#'
#' * integer kinds: integers, or doubles that are whole and in range; 64-bit
#'   kinds also decimal strings, which are exact;
#' * enums: factors, value names, or numbers (a closed enum accepts only
#'   the numbers it defines);
#' * `Timestamp`: `POSIXct` or seconds since the epoch; `Duration`:
#'   `difftime` or seconds; a wrapper: its value;
#' * `Value`: `NULL`, a logical, number or string, a named list (a
#'   `Struct`), or an unnamed list or vector (a `ListValue`).
#'
#' `bytes` fields take raw vectors (a list of them when repeated).
#'
#' @param x A named list, one element per field. For a well-known type with
#'   an R scalar form (`Timestamp`, `Duration`, wrappers), that scalar.
#' @param type The message type's full name, such as `"pkg.Message"`.
#' @param pool A pool from [proto_pool()] holding `type`.
#' @param deterministic Whether to encode deterministically: map entries
#'   sorted by key, so equal values always give equal bytes.
#' @param unknown Whether to write back unknown fields kept by
#'   `proto_decode(unknown = "keep")` in a `proto_unknown` attribute.
#' @param check_required Whether a missing proto2 `required` field is an
#'   error.
#' @param extra `"error"` to refuse names the type does not define,
#'   `"ignore"` to skip them.
#' @return A raw vector.
#' @seealso [zuproto-conditions] for the errors it raises; each one about a
#'   value carries `path`, the field at fault, such as `"points[2].x"`.
#' @export
#' @examples
#' pool <- proto_pool()
#' proto_encode(42L, "google.protobuf.Int32Value", pool)
#' when <- as.POSIXct("2026-10-25 12:00:00", tz = "UTC")
#' raw <- proto_encode(when, "google.protobuf.Timestamp", pool)
#' proto_decode(raw, "google.protobuf.Timestamp", pool)
proto_encode <- function(
  x,
  type,
  pool,
  deterministic = TRUE,
  unknown = TRUE,
  check_required = TRUE,
  extra = c("error", "ignore")
) {
  call <- sys.call()
  check_pool(pool, call = call)
  check_type(type, call = call)
  check_flag(deterministic, "deterministic", call)
  check_flag(unknown, "unknown", call)
  check_flag(check_required, "check_required", call)
  extra <- zpb_match_arg(extra, c("error", "ignore"), "extra", call)

  opts <- list(
    deterministic = as.integer(deterministic),
    check_required = as.integer(check_required),
    write_unknown = as.integer(unknown),
    ignore_extra = as.integer(extra == "ignore")
  )
  res <- .Call(zpb_encode, pool$ptr, type, x, opts)
  if (!is.null(res$error)) {
    encode_error(res, type, call)
  }
  res$value
}

encode_error <- function(res, type, call) {
  where <- if (is.null(res$path) || !nzchar(res$path)) {
    "The value"
  } else {
    sprintf("Field `%s`", res$path)
  }
  switch(
    res$error,
    unknown_type = zpb_abort(
      "zuproto_unknown_type",
      sprintf("Message type '%s' is not in the pool.", type),
      type = type,
      call = call
    ),
    type_mismatch = zpb_abort(
      "zuproto_type_mismatch",
      sprintf("Cannot encode as '%s': %s %s.", type, where, res$detail),
      path = res$path,
      call = call
    ),
    unknown_field = zpb_abort(
      "zuproto_unknown_field",
      sprintf(
        "Cannot encode as '%s': %s is not a field of the message type. Use `extra = \"ignore\"` to skip names the type does not define.",
        type,
        where
      ),
      path = res$path,
      call = call
    ),
    missing_required = zpb_abort(
      "zuproto_missing_required",
      sprintf("Cannot encode as '%s': a required field is not set.", type),
      call = call
    ),
    zpb_abort(
      "zuproto_error",
      sprintf("Cannot encode as '%s': out of memory.", type),
      call = call
    )
  )
}
