# Descriptor pools, design section 8. A pool is a list holding the external
# pointer to upb's symbol table and an environment of the files added to it,
# name -> serialised bytes. Environments give the pool reference semantics,
# which the symbol table has anyway: proto_pool_add() changes the pool it is
# given.

#' Descriptor pools
#'
#' A pool holds the message types zuproto can decode and encode. It is
#' built from serialised `FileDescriptorSet`s, which `protoc` and `buf`
#' write:
#'
#' ```sh
#' protoc --include_imports --descriptor_set_out=schema.binpb schema.proto
#' buf build -o schema.binpb
#' ```
#'
#' Every pool starts with the well-known types (`google/protobuf/*.proto`,
#' including `descriptor.proto`), so a set need not include them.
#'
#' Descriptor sets are trusted input: upb checks them, but less thoroughly
#' than `protoc` does. Load sets you or your tools produced, not ones from
#' an untrusted source. Message bytes, by contrast, are never trusted.
#'
#' Files are added in dependency order, whatever order the set lists them
#' in. A file already in the pool is skipped if its contents are identical
#' and is a `zuproto_pool_conflict` if they are not; the same holds for a
#' file listed twice. A file importing one that is neither in the set nor
#' in the pool is a `zuproto_pool_error` naming both, and nothing from the
#' set is added. Extensions are loaded with the files that declare them.
#'
#' @param x A serialised `FileDescriptorSet`: a raw vector, a path to a
#'   file, or a connection. `NULL` for the well-known types only.
#' @param pool A pool from `proto_pool()`.
#' @return `proto_pool()` returns a pool. `proto_pool_add()` returns `pool`,
#'   invisibly, after adding `x` to it.
#' @seealso [proto_types()] and [proto_fields()] to see what a pool holds.
#' @export
#' @examples
#' pool <- proto_pool()
#' pool
#' "google.protobuf.Timestamp" %in% proto_types(pool)$name
proto_pool <- function(x = NULL) {
  pool <- structure(
    list(
      ptr = .Call(zpb_pool_new),
      files = new.env(parent = emptyenv())
    ),
    class = "proto_pool"
  )
  pool_add_set(pool, wkt_bytes(), call = sys.call())
  if (!is.null(x)) {
    pool_add_set(pool, read_input(x, "x", sys.call()), call = sys.call())
  }
  pool
}

#' @rdname proto_pool
#' @export
proto_pool_add <- function(pool, x) {
  check_pool(pool, call = sys.call())
  pool_add_set(pool, read_input(x, "x", sys.call()), call = sys.call())
  invisible(pool)
}

#' @export
format.proto_pool <- function(x, ...) {
  if (!isTRUE(.Call(zpb_pool_is_valid, x$ptr))) {
    return("<proto_pool: invalid, its pointer did not survive serialisation>")
  }
  files <- ls(x$files)
  n_types <- length(.Call(zpb_pool_types, x$ptr, files)$name)
  sprintf("<proto_pool: %d files, %d message types>", length(files), n_types)
}

#' @export
print.proto_pool <- function(x, ...) {
  writeLines(format(x, ...))
  invisible(x)
}

check_pool <- function(pool, arg = "pool", call = NULL) {
  if (!inherits(pool, "proto_pool")) {
    zpb_invalid_argument(
      arg,
      sprintf("`%s` must be a pool from proto_pool().", arg),
      call
    )
  }
  if (!isTRUE(.Call(zpb_pool_is_valid, pool$ptr))) {
    zpb_invalid_argument(
      arg,
      sprintf(
        "`%s` is no longer usable: a pool does not survive saveRDS() or a new session. Build it again with proto_pool().",
        arg
      ),
      call
    )
  }
  invisible(pool)
}

wkt_bytes <- function() {
  path <- system.file(
    "descriptors",
    "wkt.binpb",
    package = "zuproto",
    mustWork = TRUE
  )
  readBin(path, "raw", file.size(path))
}

# A raw vector, a path, or a connection, as raw bytes: at most `limit` of
# them from a file or connection.
read_input <- function(x, arg, call = NULL, limit = Inf) {
  if (is.raw(x)) {
    return(x)
  }
  if (inherits(x, "connection")) {
    return(read_connection(x, call, limit))
  }
  if (is.character(x) && length(x) == 1L && !is.na(x)) {
    check_file(x, call)
    size <- min(file.size(x), limit)
    return(tryCatch(
      readBin(x, "raw", size),
      error = function(e) {
        zpb_abort(
          "zuproto_io_error",
          sprintf("Cannot read file '%s': %s", x, conditionMessage(e)),
          call = call
        )
      }
    ))
  }
  zpb_invalid_argument(
    arg,
    sprintf("`%s` must be a raw vector, a path or a connection.", arg),
    call
  )
}

# open() and readBin() on a connection, failing as zuproto_io_error.
open_connection <- function(con, call) {
  # open() warns with the reason ("No such file or directory") before it
  # fails with a generic error; the reason goes in the error. A warning
  # from an open() that succeeds is passed on (#96).
  warnings <- list()
  res <- tryCatch(
    withCallingHandlers(
      open(con, "rb"),
      warning = function(w) {
        warnings[[length(warnings) + 1L]] <<- w
        invokeRestart("muffleWarning")
      }
    ),
    error = function(e) e
  )
  if (inherits(res, "error")) {
    reason <- if (length(warnings) > 0L) warnings[[1L]] else res
    zpb_abort(
      "zuproto_io_error",
      sprintf("Cannot open connection: %s.", conditionMessage(reason)),
      call = call
    )
  }
  for (w in warnings) {
    warning(w)
  }
  invisible(con)
}

read_chunk <- function(con, n, call) {
  tryCatch(readBin(con, "raw", n), error = function(e) {
    zpb_abort(
      "zuproto_io_error",
      sprintf("Cannot read connection: %s.", conditionMessage(e)),
      call = call
    )
  })
}

read_connection <- function(con, call = NULL, limit = Inf) {
  if (!isOpen(con)) {
    open_connection(con, call)
    on.exit(close(con))
  }
  chunks <- list()
  got <- 0
  while (got < limit) {
    chunk <- read_chunk(con, min(65536, limit - got), call)
    if (length(chunk) == 0L) {
      break
    }
    chunks[[length(chunks) + 1L]] <- chunk
    got <- got + length(chunk)
  }
  unlist(chunks, use.names = FALSE) %||% raw()
}

# Base R has %||% from 4.4 only; zuproto supports 4.1.
`%||%` <- function(x, y) if (is.null(x)) y else x

# Check the whole set before adding any of it, so a set that fails leaves
# the pool as it was. upb can still reject a file the checks here pass;
# then the files before it stay added.
pool_add_set <- function(pool, bytes, call = NULL) {
  set <- .Call(zpb_set_files, bytes)
  if (is.character(set)) {
    zpb_abort(
      "zuproto_pool_error",
      sprintf("Cannot add to the pool: %s.", set),
      call = call
    )
  }

  known <- pool$files
  new <- list()
  for (i in seq_along(set$name)) {
    name <- set$name[[i]]
    bytes_i <- set$bytes[[i]]
    old <- if (exists(name, envir = known, inherits = FALSE)) {
      known[[name]]
    } else {
      new[[name]]$bytes
    }
    if (!is.null(old)) {
      if (identical(old, bytes_i)) {
        next
      }
      zpb_abort(
        c("zuproto_pool_conflict", "zuproto_pool_error"),
        sprintf(
          "Cannot add '%s': a different file of that name is already in the pool.",
          name
        ),
        file = name,
        call = call
      )
    }
    new[[name]] <- list(deps = set$deps[[i]], bytes = bytes_i)
  }

  for (name in names(new)) {
    for (dep in new[[name]]$deps) {
      if (
        !exists(dep, envir = known, inherits = FALSE) && is.null(new[[dep]])
      ) {
        zpb_abort(
          "zuproto_pool_error",
          sprintf(
            "Cannot add '%s': it imports '%s', which is neither in the set nor in the pool. Build the set with `protoc --include_imports`, or add that file first.",
            name,
            dep
          ),
          file = name,
          missing = dep,
          call = call
        )
      }
    }
  }

  # Dependency order: add a file once all it imports is there.
  pending <- names(new)
  while (length(pending) > 0L) {
    ready <- vapply(
      pending,
      function(name) {
        all(vapply(
          new[[name]]$deps,
          exists,
          logical(1),
          envir = known,
          inherits = FALSE
        ))
      },
      logical(1)
    )
    if (!any(ready)) {
      zpb_abort(
        "zuproto_pool_error",
        sprintf(
          "Cannot add the set: its imports form a cycle among %s.",
          paste0("'", pending, "'", collapse = ", ")
        ),
        file = pending[[1L]],
        call = call
      )
    }
    for (name in pending[ready]) {
      err <- .Call(zpb_pool_add_file, pool$ptr, new[[name]]$bytes)
      if (!is.null(err)) {
        zpb_abort(
          "zuproto_pool_error",
          sprintf("Cannot add '%s': %s", name, err),
          file = name,
          call = call
        )
      }
      assign(name, new[[name]]$bytes, envir = known)
    }
    pending <- pending[!ready]
  }
  invisible(pool)
}

# A path that exists and is not a directory, or a zuproto_io_error saying
# which.
check_file <- function(path, call) {
  why <- if (dir.exists(path)) {
    "it is a directory"
  } else if (!file.exists(path)) {
    "it does not exist"
  }
  if (!is.null(why)) {
    zpb_abort(
      "zuproto_io_error",
      sprintf("Cannot read file '%s': %s.", path, why),
      call = call
    )
  }
}
