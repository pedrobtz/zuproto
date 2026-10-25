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
    single <- proto_decode(raw, types[[name]], pool, int64 = "character")
    expected <- proto_encode(single, types[[name]], pool)
    for (row in zuproto:::frame_rows(
      df,
      zuproto:::case_columns(pool, types[[name]])
    )) {
      expect_identical(
        proto_encode(row, types[[name]], pool),
        expected,
        label = name
      )
    }
  }
})

test_that("columns take the shapes design section 6.2 gives them", {
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

  none <- proto_decode_df(
    list(msg_fixture("scalars_empty")),
    "zpb.decode.Scalars",
    pool,
    defaults = FALSE
  )
  expect_identical(none$f_int32, NA_integer_)

  rep <- proto_decode_df(
    list(msg_fixture("repeated")),
    "zpb.decode.Repeated",
    pool
  )
  expect_type(rep$packed, "list")
  expect_identical(rep$packed[[1]], 1:3)
  expect_s3_class(rep$points[[1]], "data.frame")
  expect_identical(rep$points[[1]]$x, c(1L, 3L))

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
  expect_identical(err$index, 1L)
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
  on.exit(close(con))
  expect_identical(proto_read_delimited(con, "zpb.decode.Choice", pool), df)
})

test_that("each is called once per chunk of chunk_rows messages", {
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
  expect_identical(err$index, 2L)
  expect_error(
    proto_write_delimited(list(x = 1L), "zpb.decode.Point", pool),
    class = "zuproto_invalid_argument"
  )
})

test_that("a message past the memory ceiling in a batch is a size limit error", {
  # 10^6 packed zeros expand past four times their size; the error path
  # must name the limit without touching the freed arena.
  n <- 1e6
  raw <- c(as.raw(0x0a), varint(n), raw(n))
  pool <- decode_pool()
  err <- expect_error(
    proto_decode_df(
      list(raw),
      "zpb.decode.Repeated",
      pool,
      max_size = length(raw)
    ),
    class = "zuproto_size_limit"
  )
  expect_identical(err$index, 1)
  stream <- c(varint(length(raw)), raw)
  expect_error(
    proto_read_delimited(
      stream,
      "zpb.decode.Repeated",
      pool,
      max_size = length(raw)
    ),
    class = "zuproto_size_limit"
  )
})
