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
