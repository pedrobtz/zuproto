# Argument checks that fail with zuproto_invalid_argument, naming the
# argument, rather than base R's unclassed errors.

# Like match.arg(): the default vector means its first element.
zpb_match_arg <- function(x, choices, arg, call = NULL) {
  if (identical(x, choices)) {
    return(choices[[1L]])
  }
  if (!is.character(x) || length(x) != 1L || is.na(x) || !x %in% choices) {
    zpb_invalid_argument(
      arg,
      sprintf(
        "`%s` must be one of %s.",
        arg,
        paste0('"', choices, '"', collapse = ", ")
      ),
      call
    )
  }
  x
}

# `int64 = "integer64"` makes bit64 vectors, so bit64 must be there to use them.
check_int64_mode <- function(int64, call = NULL) {
  if (int64 == "integer64" && !requireNamespace("bit64", quietly = TRUE)) {
    zpb_invalid_argument(
      "int64",
      '`int64 = "integer64"` needs the bit64 package. Install it, or use `int64 = "character"` for exact values.',
      call
    )
  }
  invisible(int64)
}

check_flag <- function(x, arg, call = NULL) {
  if (!is.logical(x) || length(x) != 1L || is.na(x)) {
    zpb_invalid_argument(arg, sprintf("`%s` must be TRUE or FALSE.", arg), call)
  }
  invisible(x)
}

# A whole number in [lo, hi].
check_limit <- function(x, arg, lo, hi, call = NULL) {
  ok <- is.numeric(x) &&
    length(x) == 1L &&
    !is.na(x) &&
    x == trunc(x) &&
    x >= lo &&
    x <= hi
  if (!ok) {
    zpb_invalid_argument(
      arg,
      sprintf(
        "`%s` must be a whole number from %s to %s.",
        arg,
        format(lo, scientific = FALSE),
        format(hi, scientific = FALSE)
      ),
      call
    )
  }
  invisible(x)
}

# The `n` arguments in `...`, named `dots`, that are passed on to `fun`: each named, and named as
# one of its options, so a typo is a zuproto error rather than R's.
check_dots <- function(dots, n, fun, call = NULL) {
  options <- setdiff(names(formals(fun)), c("x", "type", "pool", "..."))
  # ...names() is NULL when no argument is named, and gives an unnamed one
  # as "" (NA before R 4.1.3).
  dots <- if (is.null(dots)) rep("", n) else dots
  dots[is.na(dots)] <- ""
  bad <- dots[!dots %in% options]
  if (length(bad) > 0L) {
    zpb_invalid_argument(
      "...",
      sprintf(
        "`...` takes only %s's options (%s); not %s.",
        deparse(substitute(fun)),
        paste0("`", options, "`", collapse = ", "),
        if (!nzchar(bad[[1]])) {
          "an unnamed argument"
        } else {
          paste0("`", bad[[1]], "`")
        }
      ),
      call
    )
  }
  invisible(dots)
}
