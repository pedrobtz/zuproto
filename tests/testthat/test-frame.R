test_that("each row encodes to the same bytes as the single-message decode", {
  pool <- decode_pool()
  types <- fixture_types()
  for (name in setdiff(names(types), "scalars_big")) {
    raw <- msg_fixture(name)
    df <- proto_decode_df(
      list(raw, raw),
      types[[name]],
      pool,
      int64 = "character"
    )
    expect_identical(nrow(df), 2L)
    # Through public functions only (#44): writing the frame gives the
    # single decode's encoding, framed, once per row.
    single <- proto_decode(raw, types[[name]], pool, int64 = "character")
    expected <- proto_encode(single, types[[name]], pool)
    framed <- c(varint(length(expected)), expected)
    expect_identical(
      proto_write_delimited(df, types[[name]], pool),
      c(framed, framed),
      label = name
    )
  }
})

# Design section 6.2's column shapes, one test per kind of column (#46).
test_that("scalar columns are atomic vectors, bytes a list column", {
  pool <- decode_pool()
  df <- proto_decode_df(
    list(msg_fixture("scalars_set"), msg_fixture("scalars_empty")),
    "zpb.decode.Scalars",
    pool
  )
  expect_identical(df$f_int32, c(-42L, 0L))
  expect_identical(df$f_optional, c(0L, NA))
  expect_s3_class(df$f_enum, "factor")
  expect_identical(as.character(df$f_enum), c("HIGH", "LEVEL_UNSPECIFIED"))
  expect_identical(df$f_bytes, list(as.raw(c(0, 1, 2, 255)), raw()))
})

test_that("defaults = FALSE gives NA for fields not on the wire", {
  pool <- decode_pool()
  none <- proto_decode_df(
    list(msg_fixture("scalars_empty")),
    "zpb.decode.Scalars",
    pool,
    defaults = FALSE
  )
  expect_identical(none$f_int32, NA_integer_)
})

test_that("repeated fields are list columns, of data frames for messages", {
  pool <- decode_pool()
  rep <- proto_decode_df(
    list(msg_fixture("repeated")),
    "zpb.decode.Repeated",
    pool
  )
  expect_type(rep$packed, "list")
  expect_identical(rep$packed[[1]], 1:3)
  expect_s3_class(rep$points[[1]], "data.frame")
  expect_identical(rep$points[[1]]$x, c(1L, 3L))
})

test_that("well-known types take their R forms as columns", {
  pool <- decode_pool()
  wk <- proto_decode_df(
    list(msg_fixture("wellknown")),
    "zpb.decode.WellKnown",
    pool
  )
  expect_s3_class(wk$when, "POSIXct")
  expect_s3_class(wk$took, "difftime")
  expect_identical(wk$i32, -3L)
  expect_identical(wk$unset_wrapper, NA_integer_)
  expect_type(wk$meta, "list")
  expect_s3_class(wk$times[[1]], "POSIXct")
})

test_that("maps are list columns of named vectors", {
  pool <- decode_pool()
  maps <- proto_decode_df(list(msg_fixture("maps")), "zpb.decode.Maps", pool)
  expect_identical(maps$by_string[[1]], c(a = 1L, b = 2L))
})

test_that("a nested message is a data-frame column, NA where unset", {
  pool <- decode_pool()
  df <- proto_decode_df(
    lapply(c("choice_text", "choice_point", "choice_none"), msg_fixture),
    "zpb.decode.Choice",
    pool
  )
  expect_s3_class(df$point, "data.frame")
  expect_identical(df$point$x, c(NA, 1L, NA))
  expect_identical(df$kind_case, c("text", "point", NA))
  expect_identical(df$text, c("hi", NA, NA))
  # Point.next is a Point: no row sets it, so the recursion stops there.
  expect_identical(df$point[["next"]], c(NA, NA, NA))
})

test_that("extensions are columns under bracketed names", {
  pool <- decode_pool()
  df <- proto_decode_df(
    list(msg_fixture("legacy_ext"), msg_fixture("legacy_min")),
    "zpb.decode2.Legacy",
    pool
  )
  expect_identical(df[["[zpb.decode2.tag]"]], c("t", NA))
  expect_identical(df[["[zpb.decode2.codes]"]], list(1:2, integer()))
})

test_that("field = takes the rows from one message's repeated message field", {
  pool <- decode_pool()
  df <- proto_decode_df(
    msg_fixture("repeated"),
    "zpb.decode.Repeated",
    pool,
    field = "points"
  )
  expect_identical(df$x, c(1L, 3L))
  expect_identical(df$y, c(2L, 4L))
  expect_identical(df[["next"]]$x, c(NA, 5L))

  for (bad in c("packed", "nope")) {
    err <- expect_error(
      proto_decode_df(
        msg_fixture("repeated"),
        "zpb.decode.Repeated",
        pool,
        field = bad
      ),
      class = "zuproto_invalid_argument"
    )
    expect_identical(err$arg, "field")
  }
  expect_identical(
    nrow(proto_decode_df(raw(), "zpb.decode.Repeated", pool, field = "points")),
    0L
  )
})

test_that("an empty list gives a data frame with no rows", {
  df <- proto_decode_df(list(), "zpb.decode.Point", decode_pool())
  expect_identical(dim(df), c(0L, 3L))
})

test_that("a message that fails names its index", {
  pool <- decode_pool()
  msgs <- list(msg_fixture("nested_3"), as.raw(0xff), msg_fixture("nested_3"))
  err <- expect_error(
    proto_decode_df(msgs, "zpb.decode.Nested", pool),
    class = "zuproto_parse_error"
  )
  expect_identical(err$index, 2)
  err <- expect_error(
    proto_decode_df(msgs, "zpb.decode.Nested", pool, max_size = 3),
    class = "zuproto_size_limit"
  )
  expect_identical(err$index, 1)
})

test_that("more rows than max_rows is a row limit error", {
  pool <- decode_pool()
  msgs <- rep(list(msg_fixture("nested_3")), 3)
  err <- expect_error(
    proto_decode_df(msgs, "zpb.decode.Nested", pool, max_rows = 2),
    class = "zuproto_row_limit"
  )
  expect_s3_class(err, "zuproto_limit_error")
  expect_error(
    proto_decode_df(
      msg_fixture("repeated"),
      "zpb.decode.Repeated",
      pool,
      field = "points",
      max_rows = 1
    ),
    class = "zuproto_row_limit"
  )
  expect_error(
    proto_decode_df(msg_fixture("nested_3"), "zpb.decode.Nested", pool),
    class = "zuproto_invalid_argument"
  )
})

test_that("warnings are counted across rows", {
  pool <- decode_pool()
  raw <- as.raw(c(0x80, 0x01, 0x05)) # f_enum = 5, not in the enum
  w <- expect_warning(
    proto_decode_df(list(raw, raw, raw), "zpb.decode.Scalars", pool),
    class = "zuproto_unknown_enum"
  )
  expect_identical(w$n, 3)
})

test_that("a delimited stream round-trips through a data frame", {
  skip_if_not_installed("withr")
  pool <- decode_pool()
  msgs <- lapply(c("choice_text", "choice_point", "choice_none"), msg_fixture)
  df <- proto_decode_df(msgs, "zpb.decode.Choice", pool)
  stream <- proto_write_delimited(df, "zpb.decode.Choice", pool)
  expect_identical(
    stream,
    do.call(c, lapply(msgs, function(m) c(varint(length(m)), m)))
  )
  expect_identical(proto_read_delimited(stream, "zpb.decode.Choice", pool), df)

  path <- withr::local_tempfile(fileext = ".pb")
  expect_identical(
    proto_write_delimited(
      msgs_as_lists <- lapply(msgs, proto_decode, "zpb.decode.Choice", pool),
      "zpb.decode.Choice",
      pool,
      path = path
    ),
    path
  )
  expect_identical(proto_read_delimited(path, "zpb.decode.Choice", pool), df)
  con <- file(path, "rb")
  withr::defer(close(con))
  expect_identical(proto_read_delimited(con, "zpb.decode.Choice", pool), df)
})

test_that("each is called once per chunk of chunk_rows messages", {
  skip_if_not_installed("withr")
  pool <- decode_pool()
  raw <- msg_fixture("nested_3")
  stream <- do.call(c, rep(list(c(varint(length(raw)), raw)), 5))
  path <- withr::local_tempfile(fileext = ".pb")
  writeBin(stream, path)
  for (input in list(stream, path)) {
    sizes <- integer()
    proto_read_delimited(
      input,
      "zpb.decode.Nested",
      pool,
      each = function(df) sizes <<- c(sizes, nrow(df)),
      chunk_rows = 2
    )
    expect_identical(sizes, c(2L, 2L, 1L))
  }
})

test_that("a message that fails names its index in the whole stream", {
  pool <- decode_pool()
  raw <- msg_fixture("nested_3")
  good <- c(varint(length(raw)), raw)
  bad <- c(varint(1), as.raw(0xff))
  big <- c(varint(64), as.raw(rep(0x00, 64)))
  for (case in list(
    list(bad, "zuproto_parse_error"),
    list(big, "zuproto_size_limit")
  )) {
    stream <- c(rep(good, 5), case[[1]], good)
    read <- function(...) {
      proto_read_delimited(
        stream,
        "zpb.decode.Nested",
        pool,
        max_size = 32,
        ...
      )
    }
    err <- expect_error(read(), class = case[[2]])
    expect_identical(err$index, 6, label = case[[2]])
    err <- expect_error(
      read(each = function(df) NULL, chunk_rows = 2),
      class = case[[2]]
    )
    expect_identical(err$index, 6, label = case[[2]])
  }
})

test_that("a stream ending inside a varint or a message is a parse error", {
  pool <- decode_pool()
  raw <- msg_fixture("nested_3")
  whole <- c(varint(length(raw)), raw)
  inside_varint <- c(whole, as.raw(0x80))
  inside_message <- c(whole, varint(length(raw)), raw[1:3])
  for (stream in list(inside_varint, inside_message)) {
    expect_error(
      proto_read_delimited(stream, "zpb.decode.Nested", pool),
      class = "zuproto_parse_error"
    )
    expect_error(
      proto_read_delimited(
        stream,
        "zpb.decode.Nested",
        pool,
        each = function(df) NULL
      ),
      class = "zuproto_parse_error"
    )
  }
  expect_error(
    proto_read_delimited(
      c(varint(100), raw(10)),
      "zpb.decode.Nested",
      pool,
      max_size = 50
    ),
    class = "zuproto_size_limit"
  )
})

test_that("proto_write_delimited() names the message that fails to encode", {
  pool <- decode_pool()
  err <- expect_error(
    proto_write_delimited(
      list(list(x = 1L), list(x = "a")),
      "zpb.decode.Point",
      pool
    ),
    class = "zuproto_type_mismatch"
  )
  expect_identical(err$index, 2)
  expect_error(
    proto_write_delimited(list(x = 1L), "zpb.decode.Point", pool),
    class = "zuproto_invalid_argument"
  )
})

test_that("batches of thousands of small messages decode (the schema's ceiling)", {
  # #26: the old ceiling, four times the input, refused batches of small
  # messages after a few dozen; 5,000 rows also runs the row buffer's growth.
  pool <- decode_pool()
  types <- fixture_types()
  n <- 5000
  for (name in c(
    "maps",
    "repeated",
    "nested_3",
    "wellknown",
    "scalars_empty"
  )) {
    raw <- msg_fixture(name)
    msgs <- rep(list(raw), n)
    df <- proto_decode_df(msgs, types[[name]], pool)
    expect_identical(nrow(df), as.integer(n), label = name)
    stream <- do.call(c, rep(list(c(varint(length(raw)), raw)), n))
    expect_identical(
      nrow(proto_read_delimited(stream, types[[name]], pool)),
      as.integer(n),
      label = name
    )
  }
  points <- rep(as.raw(c(0x32, 0x00)), n) # one Repeated with 5,000 empty points
  expect_identical(
    nrow(proto_decode_df(
      points,
      "zpb.decode.Repeated",
      pool,
      field = "points"
    )),
    as.integer(n)
  )
})

test_that("a decoded frame with nested oneofs writes back as it was read", {
  # #28: the <oneof>_case columns of a message field's data frame, and of a
  # repeated one's cells, were taken for fields.
  pool <- decode_pool()
  raw <- msg_fixture("outer")
  df <- proto_decode_df(list(raw, raw), "zpb.decode.Outer", pool)
  expect_identical(df$inner$kind_case, c("text", "text"))
  expect_identical(df$items[[1]]$kind_case, c("number", "point", NA))
  stream <- proto_write_delimited(df, "zpb.decode.Outer", pool)
  expect_identical(
    stream,
    c(varint(length(raw)), raw, varint(length(raw)), raw)
  )
})

test_that("the readers and writers refuse unusable arguments", {
  # #42: argument paths no other test takes.
  pool <- decode_pool()
  raw <- msg_fixture("nested_3")
  expect_error(
    proto_read_delimited("no/such/stream.bin", "zpb.decode.Nested", pool),
    class = "zuproto_io_error"
  )
  err <- expect_error(
    proto_read_delimited(raw, "zpb.decode.Nested", pool, each = 1),
    class = "zuproto_invalid_argument"
  )
  expect_identical(err$arg, "each")
  err <- expect_error(
    proto_write_delimited(list(list()), "zpb.decode.Nested", pool, path = 1),
    class = "zuproto_invalid_argument"
  )
  expect_identical(err$arg, "path")
  err <- expect_error(
    proto_decode_df(raw, "zpb.decode.Repeated", pool, field = NA),
    class = "zuproto_invalid_argument"
  )
  expect_identical(err$arg, "field")
})

test_that("proto_to_json() reads a message from a path", {
  skip_if_not_installed("withr")
  pool <- decode_pool()
  path <- withr::local_tempfile(fileext = ".binpb")
  writeBin(msg_fixture("nested_3"), path)
  expect_identical(
    proto_to_json(path, "zpb.decode.Nested", pool),
    proto_to_json(msg_fixture("nested_3"), "zpb.decode.Nested", pool)
  )
})

test_that("a stream read with `each` fails on its connection as an io error", {
  # #47: open() and readBin() there gave base R errors.
  skip_if_not_installed("withr")
  pool <- decode_pool()
  path <- withr::local_tempfile(fileext = ".bin")
  noop <- function(df) NULL
  expect_error(
    proto_read_delimited(file(path), "zpb.decode.Nested", pool, each = noop),
    class = "zuproto_io_error"
  )
  writeBin(raw(), path)
  con <- file(path, "wb")
  withr::defer(close(con))
  expect_error(
    proto_read_delimited(con, "zpb.decode.Nested", pool, each = noop),
    class = "zuproto_io_error"
  )
})

test_that("a directory is named as one, not as missing", {
  # #49
  pool <- decode_pool()
  dir <- tempdir()
  for (f in list(
    function() proto_pool(dir),
    function() proto_decode(dir, "zpb.decode.Nested", pool),
    function() {
      proto_read_delimited(dir, "zpb.decode.Nested", pool, each = print)
    }
  )) {
    err <- expect_error(f(), class = "zuproto_io_error")
    expect_match(conditionMessage(err), "it is a directory", fixed = TRUE)
  }
})
