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

zpb_invalid_argument <- function(arg, message, call = NULL) {
  zpb_abort("zuproto_invalid_argument", message, arg = arg, call = call)
}
