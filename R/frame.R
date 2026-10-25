# Many messages as one data frame (design sections 6.2, 6.4 and 10). C
# decodes every message into one arena and builds the frame column by
# column; R checks arguments, reads input and raises.

#' Decode many messages into a data frame
#'
#' Decodes many messages of one type into a data frame, one row per
#' message, built column by column: every message is decoded first, then
#' each column is filled across all of them. A message that fails stops the
#' whole call, and the condition's `index` says which one.
#'
#' With `field`, the input is one message instead, and the rows are the
#' elements of its repeated message field `field`. That is how feeds that
#' wrap their records in one message become tables, a GTFS Realtime
#' `FeedMessage` and its `entity` field for one.
#'
#' @section Columns:
#' | Field | Column |
#' | --- | --- |
#' | scalar, enum, scalar-like well-known type | atomic vector, as in [proto_decode()] |
#' | `bytes` | list of raw vectors |
#' | message | data frame (a column of the frame) |
#' | `repeated` scalar | list of vectors |
#' | `repeated` message | list of data frames |
#' | `map` | list of named vectors or lists |
#' | `Struct`, `Value`, `ListValue`, `Any` | list, as in [proto_decode()] |
#' | `oneof` | a column per member, plus `<oneof>_case` with the member set |
#' | extension | a column named `[pkg.ext]` per extension the pool knows |
#'
#' A field a row does not set is `NA` (`NULL` in a list column) when the
#' field tracks presence; otherwise it takes its default, or is `NA` with
#' `defaults = FALSE`. A message field that no row sets is an all-`NA`
#' logical column rather than a data frame, which is also where the columns
#' of a recursive type end. A message type with no fields, such as `Empty`,
#' is a list column: `list()` where set, `NULL` where not. A nested message
#' that is set but has every field unset reads as unset, since its row is
#' all `NA`.
#'
#' @inheritParams proto_decode
#' @param x For `proto_decode_df()`, a list of raw vectors, one message
#'   each; with `field`, one message as a raw vector, a path or a
#'   connection. For `proto_read_delimited()`, a raw vector, a path or a
#'   connection holding a length-delimited stream.
#' @param field The name of a repeated message field of `type`, or `NULL`.
#' @param max_rows The largest number of rows accepted.
#' @return A data frame.
#' @seealso [proto_read_delimited()] for length-delimited streams.
#' @export
#' @examples
#' pool <- proto_pool()
#' # Three FieldDescriptorProto messages, one per row.
#' msgs <- lapply(c("id", "name", "when"), function(name) {
#'   proto_encode(list(name = name, number = 1L), "google.protobuf.FieldDescriptorProto", pool)
#' })
#' df <- proto_decode_df(msgs, "google.protobuf.FieldDescriptorProto", pool)
#' df[c("name", "number")]
proto_decode_df <- function(
  x,
  type,
  pool,
  field = NULL,
  int64 = c("double", "character"),
  enums = c("factor", "integer", "character"),
  defaults = TRUE,
  bytes = c("raw", "base64"),
  max_size = zpb_default_limits()$max_size,
  max_depth = zpb_default_limits()$max_depth,
  max_rows = 1e7
) {
  call <- sys.call()
  opts <- df_options(
    pool,
    type,
    int64,
    enums,
    defaults,
    bytes,
    max_size,
    max_depth,
    max_rows,
    call
  )
  if (is.null(field)) {
    if (!is.list(x) || !all(vapply(x, is.raw, logical(1)))) {
      zpb_invalid_argument(
        "x",
        "`x` must be a list of raw vectors, one message each. For one message holding the rows in a repeated field, give `field`; for a length-delimited stream, use proto_read_delimited().",
        call
      )
    }
    if (length(x) > max_rows) {
      row_limit(max_rows, call)
    }
    sizes <- lengths(x)
    big <- which(sizes > max_size)
    if (length(big) > 0L) {
      zpb_abort(
        c("zuproto_size_limit", "zuproto_limit_error"),
        sprintf(
          "Message %d is larger than `max_size` (%s bytes).",
          big[[1L]],
          format(max_size, scientific = FALSE)
        ),
        limit = "max_size",
        limit_value = max_size,
        index = big[[1L]],
        call = call
      )
    }
    opts$mode <- 0L
    opts$arena_limit <- max(4 * sum(sizes), 65536)
  } else {
    if (
      !is.character(field) ||
        length(field) != 1L ||
        is.na(field) ||
        !nzchar(field)
    ) {
      zpb_invalid_argument(
        "field",
        "`field` must be a field name, a single string.",
        call
      )
    }
    x <- read_message(x, max_size, call)
    opts$mode <- 1L
    opts$field <- field
    opts$arena_limit <- max(4 * length(x), 65536)
  }
  res <- .Call(zpb_decode_df, pool$ptr, type, x, opts)
  df_finish(res, type, field, max_size, max_depth, max_rows, call)
}

#' Length-delimited streams
#'
#' `proto_read_delimited()` reads a stream of messages, each preceded by its
#' length as a varint, as Java's `writeDelimitedTo()`, Python's
#' `_VarintBytes` helpers and many `.pb` log files write them, into a data
#' frame like [proto_decode_df()] builds. With `each`, it reads the stream
#' in chunks of `chunk_rows` messages and calls `each(df)` on each chunk
#' instead, so a stream larger than memory can be processed.
#' `proto_write_delimited()` writes one.
#'
#' A stream that ends inside a length or a message is a
#' `zuproto_parse_error`.
#'
#' @inheritParams proto_decode_df
#' @param each `NULL`, or a function called with each chunk's data frame.
#' @param chunk_rows The number of messages in each chunk given to `each`.
#' @return `proto_read_delimited()`: a data frame, or with `each`, `NULL`,
#'   invisibly.
#' @export
#' @examples
#' pool <- proto_pool()
#' rows <- data.frame(seconds = c(1, 2, 3), nanos = 0L)
#' stream <- proto_write_delimited(rows, "google.protobuf.Duration", pool)
#' proto_read_delimited(stream, "google.protobuf.Duration", pool)
proto_read_delimited <- function(
  x,
  type,
  pool,
  each = NULL,
  chunk_rows = 10000,
  int64 = c("double", "character"),
  enums = c("factor", "integer", "character"),
  defaults = TRUE,
  bytes = c("raw", "base64"),
  max_size = zpb_default_limits()$max_size,
  max_depth = zpb_default_limits()$max_depth,
  max_rows = 1e7
) {
  call <- sys.call()
  opts <- df_options(
    pool,
    type,
    int64,
    enums,
    defaults,
    bytes,
    max_size,
    max_depth,
    max_rows,
    call
  )
  if (!is.null(each) && !is.function(each)) {
    zpb_invalid_argument("each", "`each` must be a function or NULL.", call)
  }
  check_limit(chunk_rows, "chunk_rows", 1, 1e9, call)
  opts$mode <- 2L

  if (is.null(each)) {
    buf <- read_input(x, "x", call)
    opts$chunk_rows <- max_rows + 1
    opts$arena_limit <- max(4 * length(buf), 65536)
    res <- .Call(zpb_decode_df, pool$ptr, type, buf, opts)
    df <- df_finish(res, type, NULL, max_size, max_depth, max_rows, call)
    if (res$consumed < length(buf)) {
      truncated(length(buf) - res$consumed, call)
    }
    return(df)
  }

  opts$chunk_rows <- chunk_rows
  con <- NULL
  if (is.raw(x)) {
    pending <- x
  } else {
    con <- if (inherits(x, "connection")) x else open_path(x, call)
    if (!isOpen(con)) {
      open(con, "rb")
      on.exit(close(con), add = TRUE)
    } else if (!inherits(x, "connection")) {
      on.exit(close(con), add = TRUE)
    }
    pending <- raw()
  }
  eof <- is.null(con)
  need_more <- TRUE
  repeat {
    # Read only when the bytes in hand hold no whole chunk of messages.
    if (need_more && !eof) {
      chunk <- readBin(con, "raw", 1048576L)
      if (length(chunk) == 0L) eof <- TRUE else pending <- c(pending, chunk)
    }
    if (length(pending) == 0L && eof) {
      break
    }
    opts$arena_limit <- max(4 * length(pending), 65536)
    res <- .Call(zpb_decode_df, pool$ptr, type, pending, opts)
    df <- df_finish(res, type, NULL, max_size, max_depth, max_rows, call)
    if (nrow(df) > 0L) {
      each(df)
    }
    used <- res$consumed
    if (used == 0 && eof) {
      truncated(length(pending), call)
    }
    pending <- pending[seq_len(length(pending) - used) + used]
    need_more <- nrow(df) < chunk_rows
  }
  invisible(NULL)
}

#' @rdname proto_read_delimited
#' @param path `NULL` to return the stream, or a path to write it to.
#' @param ... Passed to [proto_encode()] for each message.
#' @return `proto_write_delimited()`: the stream as a raw vector, or with
#'   `path`, the path, invisibly.
#' @details `proto_write_delimited()` takes a data frame whose columns
#'   follow the column table of [proto_decode_df()], one message per row,
#'   or a list of messages as [proto_encode()] takes them. `NA` values leave
#'   fields unset, and `<oneof>_case` columns are ignored.
#' @export
proto_write_delimited <- function(x, type, pool, path = NULL, ...) {
  call <- sys.call()
  check_pool(pool, call = call)
  check_type(type, call = call)
  if (
    !is.null(path) && (!is.character(path) || length(path) != 1L || is.na(path))
  ) {
    zpb_invalid_argument("path", "`path` must be NULL or a single path.", call)
  }
  if (is.data.frame(x)) {
    msgs <- frame_rows(x, case_columns(pool, type))
  } else if (is.list(x) && is.null(names(x))) {
    msgs <- x
  } else {
    zpb_invalid_argument(
      "x",
      "`x` must be a data frame, one message per row, or an unnamed list of messages.",
      call
    )
  }
  raws <- vector("list", length(msgs))
  for (i in seq_along(msgs)) {
    raws[[i]] <- tryCatch(
      proto_encode(msgs[[i]], type, pool, ...),
      zuproto_error = function(e) {
        e$message <- sprintf("Message %d: %s", i, conditionMessage(e))
        e$index <- i
        e$call <- call
        stop(e)
      }
    )
  }
  stream <- .Call(zpb_frame_delimited, raws)
  if (is.null(path)) {
    return(stream)
  }
  writeBin(stream, path)
  invisible(path)
}

# ---- helpers ----

df_options <- function(
  pool,
  type,
  int64,
  enums,
  defaults,
  bytes,
  max_size,
  max_depth,
  max_rows,
  call
) {
  check_pool(pool, call = call)
  check_type(type, call = call)
  int64 <- zpb_match_arg(int64, c("double", "character"), "int64", call)
  enums <- zpb_match_arg(
    enums,
    c("factor", "integer", "character"),
    "enums",
    call
  )
  bytes <- zpb_match_arg(bytes, c("raw", "base64"), "bytes", call)
  check_flag(defaults, "defaults", call)
  check_limit(max_size, "max_size", 1, 2^53, call)
  check_limit(max_depth, "max_depth", 1, 1000, call)
  check_limit(max_rows, "max_rows", 1, 2^31 - 1, call)
  list(
    int64 = match(int64, c("double", "character")) - 1L,
    enums = match(enums, c("factor", "integer", "character")) - 1L,
    defaults = as.integer(defaults),
    bytes_base64 = as.integer(bytes == "base64"),
    max_depth = as.integer(max_depth),
    max_size = as.double(max_size),
    max_rows = as.double(max_rows),
    chunk_rows = Inf,
    field = ""
  )
}

df_finish <- function(res, type, field, max_size, max_depth, max_rows, call) {
  if (!is.null(res$error)) {
    switch(
      res$error,
      bad_field = zpb_invalid_argument(
        "field",
        sprintf(
          "`field` must name a repeated message field of '%s'; '%s' does not.",
          type,
          field
        ),
        call
      ),
      max_rows = row_limit(max_rows, call),
      max_size = zpb_abort(
        c("zuproto_size_limit", "zuproto_limit_error"),
        sprintf(
          "Message %s of the stream is larger than `max_size` (%s bytes).",
          format(res$index),
          format(max_size, scientific = FALSE)
        ),
        limit = "max_size",
        limit_value = max_size,
        index = res$index,
        call = call
      ),
      tryCatch(
        decode_error(res, type, max_size, max_depth, call),
        zuproto_error = function(e) {
          if (res$index > 0) {
            e$message <- sprintf(
              "Message %s: %s",
              format(res$index),
              conditionMessage(e)
            )
            e$index <- res$index
          }
          stop(e)
        }
      )
    )
  }
  decode_warnings(res, type, call)
  res$value
}

row_limit <- function(max_rows, call) {
  zpb_abort(
    c("zuproto_row_limit", "zuproto_limit_error"),
    sprintf(
      "There are more than `max_rows` (%s) rows.",
      format(max_rows, scientific = FALSE)
    ),
    limit = "max_rows",
    limit_value = max_rows,
    call = call
  )
}

truncated <- function(remaining, call) {
  zpb_abort(
    "zuproto_parse_error",
    sprintf(
      "The stream ends inside a message or its length: %s bytes after the last whole message.",
      format(remaining, scientific = FALSE)
    ),
    status = "truncated",
    call = call
  )
}

open_path <- function(x, call) {
  if (!is.character(x) || length(x) != 1L || is.na(x)) {
    zpb_invalid_argument(
      "x",
      "`x` must be a raw vector, a path or a connection.",
      call
    )
  }
  if (!file.exists(x) || dir.exists(x)) {
    zpb_abort(
      "zuproto_io_error",
      sprintf("Cannot read file '%s': it does not exist.", x),
      call = call
    )
  }
  file(x, "rb")
}

# Names of the `<oneof>_case` columns of type, which encoding skips.
case_columns <- function(pool, type) {
  f <- proto_fields(pool, type)
  paste0(unique(f$oneof[!is.na(f$oneof)]), "_case")
}

# A data frame's rows as messages for proto_encode(): a column's element i,
# a list column's element, a data-frame column's row i as a message.
frame_rows <- function(df, skip = character()) {
  cols <- df[setdiff(names(df), skip)]
  lapply(seq_len(nrow(df)), function(i) frame_row(cols, i))
}

frame_row <- function(cols, i) {
  out <- lapply(cols, function(col) {
    if (is.data.frame(col)) {
      row <- frame_row(col, i)
      if (length(row) == 0L) NULL else row
    } else if (is.list(col)) {
      v <- col[[i]]
      # A repeated message field's cell is a data frame of its elements.
      if (is.data.frame(v)) frame_rows(v) else v
    } else {
      v <- col[i]
      if (is.na(v)) NULL else v
    }
  })
  out[!vapply(out, is.null, logical(1))]
}
