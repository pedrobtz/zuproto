#' Message types and their fields
#'
#' `proto_types()` lists every message type in a pool, nested types
#' included, as a data frame. `proto_fields()` lists the fields of one
#' type, followed by the extensions the pool knows for it.
#'
#' An extension is named by its full name in brackets, as in protobuf's
#' JSON mapping, for example `"[transit_realtime.trip_descriptor_ext]"`.
#' Decoded messages use the same names.
#'
#' @param pool A pool from [proto_pool()].
#' @param type A message type's full name, such as `"google.protobuf.Timestamp"`.
#' @return `proto_types()`: a data frame with columns `name` (full name),
#'   `file` (the `.proto` file declaring it) and `fields` (the number of
#'   fields), sorted by name. Map entry types are left out.
#'
#'   `proto_fields()`: a data frame with one row per field and columns
#'   * `name`: the field's name, or `[full.name]` for an extension;
#'   * `number`: the field number;
#'   * `type`: the protobuf type, such as `"int32"`, `"string"`,
#'     `"message"` or `"enum"`;
#'   * `label`: `"optional"`, `"required"` or `"repeated"`;
#'   * `type_name`: the message or enum type's full name, `NA` for scalars;
#'   * `oneof`: the oneof the field belongs to, or `NA`;
#'   * `json_name`: the name in protobuf JSON;
#'   * `presence`: whether the field tracks whether it is set;
#'   * `packed`: whether repeated values are packed on the wire;
#'   * `map`: whether the field is a map;
#'   * `extension`: whether the field is an extension.
#' @export
#' @examples
#' pool <- proto_pool()
#' head(proto_types(pool))
#' proto_fields(pool, "google.protobuf.Timestamp")
proto_types <- function(pool) {
  check_pool(pool, call = sys.call())
  cols <- .Call(zpb_pool_types, pool$ptr, sort(ls(pool$files)))
  out <- data.frame(name = cols$name, file = cols$file, fields = cols$fields)
  out <- out[order(out$name, method = "radix"), , drop = FALSE]
  rownames(out) <- NULL
  out
}

#' @rdname proto_types
#' @export
proto_fields <- function(pool, type) {
  check_pool(pool, call = sys.call())
  check_type(type, call = sys.call())
  cols <- .Call(zpb_pool_fields, pool$ptr, type)
  if (is.null(cols)) {
    zpb_abort(
      "zuproto_unknown_type",
      sprintf("Message type '%s' is not in the pool.", type),
      type = type,
      call = sys.call()
    )
  }
  as.data.frame(cols)
}

check_type <- function(type, arg = "type", call = NULL) {
  if (
    !is.character(type) || length(type) != 1L || is.na(type) || !nzchar(type)
  ) {
    zpb_invalid_argument(
      arg,
      sprintf("`%s` must be a message type's full name, a single string.", arg),
      call
    )
  }
  invisible(type)
}
