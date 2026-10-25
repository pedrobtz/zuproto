#' Build information
#'
#' Reports the zuproto version and the Protocol Buffers release whose upb
#' runtime is bundled.
#'
#' @return A list of class `zuproto_info` with elements:
#'   * `version`: zuproto's version.
#'   * `protobuf`: the protobuf release tag upb was vendored from, such as
#'     `"v36.2"`.
#'   * `protobuf_commit`: that tag's commit.
#'   * `limits`: the default `max_size` (bytes) and `max_depth` of
#'     [proto_decode()].
#' @export
#' @examples
#' zuproto_info()
zuproto_info <- function() {
  info <- .Call(zpb_build_info)
  structure(
    list(
      version = unname(getNamespaceVersion("zuproto")),
      protobuf = info$protobuf_tag,
      protobuf_commit = info$protobuf_commit,
      limits = zpb_default_limits()
    ),
    class = "zuproto_info"
  )
}

#' @export
format.zuproto_info <- function(x, ...) {
  c(
    "<zuproto_info>",
    paste0("zuproto:  ", x$version),
    paste0(
      "upb:      protobuf ",
      x$protobuf,
      " (",
      substr(x$protobuf_commit, 1, 7),
      ")"
    ),
    paste0(
      "max_size: ",
      format(x$limits$max_size, scientific = FALSE),
      " bytes"
    ),
    paste0("max_depth: ", x$limits$max_depth)
  )
}

#' @export
print.zuproto_info <- function(x, ...) {
  writeLines(format(x, ...))
  invisible(x)
}
