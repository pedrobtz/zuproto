# The condition hierarchy of design section 11. The class is the contract:
# callers branch on it and on the fields below, never on the message.

#' Conditions raised by zuproto
#'
#' Every error zuproto raises carries a condition class, so it can be caught
#' by kind rather than by matching the message, which may change. Every
#' class below inherits from `zuproto_error`.
#'
#' \describe{
#'   \item{`zuproto_invalid_argument`}{An argument was unusable, such as a
#'     pool that is not one, or a type name that is not a single string.
#'     Carries `arg`, the argument at fault.}
#'   \item{`zuproto_io_error`}{A file could not be opened or read, or a
#'     connection could not be read from.}
#'   \item{`zuproto_pool_error`}{A descriptor set could not be added to a
#'     pool: the bytes are not a `FileDescriptorSet`, a file imports one
#'     that is neither in the set nor in the pool, or upb rejected a file.
#'     Carries `file`, the file at fault, when there is one.}
#'   \item{`zuproto_pool_conflict`}{A subclass of `zuproto_pool_error`: a
#'     file of the same name is already in the pool, or earlier in the set,
#'     with different contents. Carries `file`.}
#'   \item{`zuproto_unknown_type`}{A message type is not in the pool.
#'     Carries `type`.}
#'   \item{`zuproto_parse_error`}{The input is not a valid message of the
#'     type: it ends early, has a bad tag, a length beyond the input, or the
#'     wrong wire type. Carries `status`.}
#'   \item{In a batch or stream}{An error about one message of
#'     [proto_decode_df()], [proto_read_delimited()] or
#'     [proto_write_delimited()] also carries `index`, the message's
#'     position, as a double (a stream can hold more than 2^31 - 1).}
#'   \item{`zuproto_invalid_utf8`}{A subclass of `zuproto_parse_error`: a
#'     `string` field is not valid UTF-8, in proto2 as in proto3.}
#'   \item{`zuproto_unrepresentable`}{The input is valid but holds a value
#'     R cannot: a string containing a NUL byte, or longer than an R string
#'     may be. Carries `field`, the field's full name.}
#'   \item{`zuproto_type_mismatch`}{[proto_encode()] was given a value of
#'     the wrong form for its field: the wrong R type, a number out of
#'     range or not whole, a name that is not a value of the enum, `NA`
#'     inside a repeated field, a string that is not valid UTF-8 text, a
#'     date or time where a number is expected (or a `Date` for a
#'     `Timestamp`), a second member of a oneof, or a field or map key
#'     given twice. Carries `path`, the field at fault, such as
#'     `"points[2].x"`.}
#'   \item{`zuproto_unknown_field`}{[proto_encode()] was given a name the
#'     message type does not define. Carries `path`.}
#'   \item{`zuproto_missing_required`}{[proto_encode()] with
#'     `check_required = TRUE`: a proto2 `required` field is not set.}
#'   \item{`zuproto_json_error`}{[proto_from_json()] was given JSON that is
#'     not valid, or not the type's, or [proto_to_json()] could not write a
#'     message (an `Any` whose packed type is not in the pool). Carries
#'     `detail`, upb's description.}
#'   \item{`zuproto_limit_error`}{A limit was reached. The subclasses
#'     `zuproto_size_limit` (the input, or the memory decoding it needs,
#'     is too large for `max_size`), `zuproto_depth_limit` (messages nest
#'     deeper than `max_depth`) and `zuproto_row_limit` (more rows than
#'     `max_rows`) name which. Carries `limit`, the
#'     argument's name, and `limit_value`. [proto_encode()] raises
#'     `zuproto_depth_limit` for messages nested deeper than 1000 levels,
#'     the most `max_depth` lets [proto_decode()] accept.}
#'   \item{`zuproto_internal_error`}{Memory ran out, or upb reported a
#'     status zuproto does not expect. Carries `code`.}
#' }
#'
#' Warnings inherit `zuproto_warning`:
#'
#' \describe{
#'   \item{`zuproto_precision_loss`}{Values could not be represented
#'     exactly: 64-bit integers beyond 2^53 decoded as doubles, or a 32-bit
#'     `-2^31`, which R reserves for `NA`. Carries `n`, how many.}
#'   \item{`zuproto_unknown_enum`}{Enum numbers the enum does not define
#'     became `NA`. Carries `n`.}
#' }
#'
#' @name zuproto-conditions
#' @examples
#' pool <- proto_pool()
#' tryCatch(
#'   proto_fields(pool, "no.such.Message"),
#'   zuproto_unknown_type = function(e) e$type
#' )
NULL

zpb_abort <- function(class, message, ..., call = NULL) {
  stop(structure(
    class = c(class, "zuproto_error", "error", "condition"),
    list(message = message, call = call, ...)
  ))
}

zpb_warn <- function(class, message, ..., call = NULL) {
  warning(structure(
    class = c(class, "zuproto_warning", "warning", "condition"),
    list(message = message, call = call, ...)
  ))
}

# An error code the C side returned that is no user error: memory ran out,
# or upb reported a status zuproto does not map.
abort_internal <- function(code, what, call = NULL) {
  zpb_abort(
    "zuproto_internal_error",
    if (identical(code, "out_of_memory")) {
      sprintf("Cannot %s: out of memory.", what)
    } else {
      sprintf("Cannot %s: internal error '%s'.", what, code)
    },
    code = code,
    call = call
  )
}

# Called from C, by zpb_internal_error() in src/zpb_pool.c: a failure the C
# side raises directly, such as memory running out or a pointer that is not
# a pool's.
zpb_raise_internal <- function(message) {
  zpb_abort(
    "zuproto_internal_error",
    sprintf("zuproto internal error: %s.", message),
    code = "internal"
  )
}

zpb_invalid_argument <- function(arg, message, call = NULL) {
  zpb_abort("zuproto_invalid_argument", message, arg = arg, call = call)
}
