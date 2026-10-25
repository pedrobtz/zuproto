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
#' @export
#' @examples
#' zuproto_info()
zuproto_info <- function() {
  info <- .Call(zpb_build_info)
  structure(
    list(
      version = unname(getNamespaceVersion("zuproto")),
      protobuf = info$protobuf_tag,
      protobuf_commit = info$protobuf_commit
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
    )
  )
}

#' @export
print.zuproto_info <- function(x, ...) {
  writeLines(format(x, ...))
  invisible(x)
}
