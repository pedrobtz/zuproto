test_that("re-encoding a fixture gives Python's deterministic bytes", {
  pool <- decode_pool()
  types <- fixture_types()
  # wellknown's Timestamp is rounded to the microsecond on decode, and
  # scalars_big's -2^31 values decode as NA: neither comes back as it was.
  for (name in setdiff(names(types), c("wellknown", "scalars_big"))) {
    raw <- msg_fixture(name)
    x <- proto_decode(
      raw,
      types[[name]],
      pool,
      int64 = "character",
      unknown = "keep"
    )
    expect_identical(proto_encode(x, types[[name]], pool), raw, label = name)
  }
})

test_that("decode, encode, decode is the identity on every fixture", {
  pool <- decode_pool()
  types <- fixture_types()
  for (name in setdiff(names(types), "scalars_big")) {
    x <- proto_decode(
      msg_fixture(name),
      types[[name]],
      pool,
      int64 = "character",
      unknown = "keep"
    )
    y <- proto_decode(
      proto_encode(x, types[[name]], pool),
      types[[name]],
      pool,
      int64 = "character",
      unknown = "keep"
    )
    expect_identical(y, x, label = name)
  }
})

test_that("64-bit extremes round-trip as strings", {
  pool <- decode_pool()
  x <- list(
    f_int64 = "-9223372036854775808",
    f_uint64 = "18446744073709551615",
    f_sfixed64 = "9223372036854775807"
  )
  raw <- proto_encode(x, "zpb.decode.Scalars", pool)
  y <- proto_decode(
    raw,
    "zpb.decode.Scalars",
    pool,
    int64 = "character",
    defaults = FALSE
  )
  expect_identical(y, x[c("f_int64", "f_uint64", "f_sfixed64")])
})

test_that("values built in R encode as the mapping says", {
  pool <- decode_pool()
  levels <- c("LEVEL_UNSPECIFIED", "LOW", "HIGH")
  scalars <- list(
    f_double = 1.5,
    f_float = 0.25,
    f_int32 = -42,
    f_uint32 = 4e9,
    f_int64 = 2^40,
    f_bool = TRUE,
    f_string = "é",
    f_bytes = as.raw(1:3),
    f_enum = "HIGH",
    f_optional = 0L
  )
  y <- proto_decode(
    proto_encode(scalars, "zpb.decode.Scalars", pool),
    "zpb.decode.Scalars",
    pool,
    defaults = FALSE
  )
  expect_identical(
    y[names(scalars)],
    modifyList(
      scalars,
      list(
        f_int32 = -42L,
        f_enum = factor("HIGH", levels = levels)
      )
    )
  )

  reps <- list(
    packed = c(1, 2),
    levels = factor(c("LOW", "HIGH"), levels = levels),
    points = list(list(x = 1L), list(y = 2L)),
    blobs = list(as.raw(9))
  )
  y <- proto_decode(
    proto_encode(reps, "zpb.decode.Repeated", pool),
    "zpb.decode.Repeated",
    pool,
    defaults = FALSE
  )
  expect_identical(y$packed, 1:2)
  expect_identical(y$points, list(list(x = 1L), list(y = 2L)))
  expect_identical(y$blobs, list(as.raw(9)))

  maps <- list(
    by_int64 = c(`-5` = "a", `7` = "b"),
    by_bool = c(true = "t"),
    points = list(`3` = list(x = 3L)),
    levels = c(k = "LOW")
  )
  y <- proto_decode(
    proto_encode(maps, "zpb.decode.Maps", pool),
    "zpb.decode.Maps",
    pool,
    defaults = FALSE
  )
  expect_identical(y$by_int64, maps$by_int64)
  expect_identical(y$by_bool, maps$by_bool)
  expect_identical(y$points, maps$points)
  expect_identical(as.character(y$levels), "LOW")
})

test_that("well-known types encode from their R forms", {
  pool <- decode_pool()
  when <- as.POSIXct("1969-12-31 23:59:59.75", tz = "UTC") # before 1970, with a fraction
  wk <- list(
    when = when,
    took = as.difftime(-1.5, units = "mins"),
    i32 = 7L,
    text = "w",
    blob = as.raw(5),
    meta = list(n = 1, l = list(TRUE, NULL), s = list(k = "v")),
    value = NULL,
    list = c(1, 2),
    any = list(type_url = "t/x", value = as.raw(1)),
    mask = c("a", "b.c"),
    times = c(when, when + 1)
  )
  y <- proto_decode(
    proto_encode(wk, "zpb.decode.WellKnown", pool),
    "zpb.decode.WellKnown",
    pool
  )
  expect_equal(
    unclass(y$when),
    unclass(when),
    tolerance = 0,
    ignore_attr = TRUE
  )
  expect_identical(y$took, as.difftime(-90, units = "secs"))
  expect_identical(y$i32, 7L)
  expect_identical(y$blob, as.raw(5))
  expect_identical(y$meta, list(l = list(TRUE, NULL), n = 1, s = list(k = "v")))
  # NULL in a Value field is JSON null, which decodes back as a NULL
  # element; leaving the field out is what leaves it unset.
  expect_true("value" %in% names(y))
  expect_null(y$value)
  z <- proto_decode(
    proto_encode(wk[setdiff(names(wk), "value")], "zpb.decode.WellKnown", pool),
    "zpb.decode.WellKnown",
    pool
  )
  expect_false("value" %in% names(z))
  expect_identical(y$list, list(1, 2))
  expect_identical(y$any, wk$any)
  expect_identical(y$mask, wk$mask)
  expect_equal(
    unclass(y$times),
    unclass(wk$times),
    tolerance = 0,
    ignore_attr = TRUE
  )
})

test_that("NA and NULL leave fields unset", {
  pool <- decode_pool()
  x <- list(
    f_int32 = NA_integer_,
    f_string = NA_character_,
    f_enum = factor(NA),
    f_optional = NA,
    f_bytes = NULL
  )
  expect_identical(proto_encode(x, "zpb.decode.Scalars", pool), raw())
})

test_that("extensions encode under bracketed names", {
  pool <- decode_pool()
  x <- list(id = 1L, `[zpb.decode2.tag]` = "t", `[zpb.decode2.codes]` = 4:5)
  y <- proto_decode(
    proto_encode(x, "zpb.decode2.Legacy", pool),
    "zpb.decode2.Legacy",
    pool
  )
  expect_identical(y[["[zpb.decode2.tag]"]], "t")
  expect_identical(y[["[zpb.decode2.codes]"]], 4:5)
})

test_that("deterministic encoding sorts map entries", {
  pool <- decode_pool()
  a <- proto_encode(
    list(by_string = c(b = 2L, a = 1L)),
    "zpb.decode.Maps",
    pool
  )
  b <- proto_encode(
    list(by_string = c(a = 1L, b = 2L)),
    "zpb.decode.Maps",
    pool
  )
  expect_identical(a, b)
})

test_that("a name the type does not define is an unknown field, or ignored", {
  pool <- decode_pool()
  err <- expect_error(
    proto_encode(list(x = 1L, nope = 2L), "zpb.decode.Point", pool),
    class = "zuproto_unknown_field"
  )
  expect_identical(err$path, "nope")
  err <- expect_error(
    proto_encode(
      list(points = list(list(x = 1L, z = 2L))),
      "zpb.decode.Repeated",
      pool
    ),
    class = "zuproto_unknown_field"
  )
  expect_identical(err$path, "points[1].z")
  expect_identical(
    proto_encode(
      list(x = 1L, nope = 2L),
      "zpb.decode.Point",
      pool,
      extra = "ignore"
    ),
    proto_encode(list(x = 1L), "zpb.decode.Point", pool)
  )
  expect_error(
    proto_encode(list(`[no.ext]` = 1L), "zpb.decode2.Legacy", pool),
    class = "zuproto_unknown_field"
  )
})

test_that("values of the wrong form are type mismatches naming the field", {
  pool <- decode_pool()
  # Each case is labelled with its value, so a failure names the case (#46).
  mismatch <- function(x, type, path) {
    label <- deparse1(substitute(x))
    err <- expect_error(
      proto_encode(x, type, pool),
      class = "zuproto_type_mismatch",
      label = label
    )
    expect_identical(err$path, path, label = label)
  }
  mismatch(list(f_int32 = "1"), "zpb.decode.Scalars", "f_int32")
  mismatch(list(f_int32 = 1.5), "zpb.decode.Scalars", "f_int32")
  mismatch(list(f_int32 = 2^31), "zpb.decode.Scalars", "f_int32")
  mismatch(list(f_uint32 = -1), "zpb.decode.Scalars", "f_uint32")
  mismatch(list(f_int64 = "12x"), "zpb.decode.Scalars", "f_int64")
  mismatch(list(f_int64 = 2^63), "zpb.decode.Scalars", "f_int64")
  mismatch(list(f_uint64 = "-1"), "zpb.decode.Scalars", "f_uint64")
  mismatch(list(f_bool = 1), "zpb.decode.Scalars", "f_bool")
  mismatch(list(f_int32 = 1:2), "zpb.decode.Scalars", "f_int32")
  mismatch(list(f_bytes = "AQ=="), "zpb.decode.Scalars", "f_bytes")
  mismatch(list(f_enum = "MEDIUM"), "zpb.decode.Scalars", "f_enum")
  mismatch(list(f_enum = factor("MEDIUM")), "zpb.decode.Scalars", "f_enum")
  mismatch(list(packed = c(1, NA)), "zpb.decode.Repeated", "packed[2]")
  mismatch(
    list(points = list(list(x = "a"))),
    "zpb.decode.Repeated",
    "points[1].x"
  )
  mismatch(list(points = 1:2), "zpb.decode.Repeated", "points")
  mismatch(
    list(by_int32 = c(`1.5` = "a")),
    "zpb.decode.Maps",
    'by_int32["1.5"]'
  )
  mismatch(list(by_bool = c(yes = "a")), "zpb.decode.Maps", 'by_bool["yes"]')
  mismatch(
    list(by_string = c(a = 1L, a = 2L)),
    "zpb.decode.Maps",
    'by_string["a"]'
  )
  mismatch(list(by_string = 1:2), "zpb.decode.Maps", "by_string")
  mismatch(list(text = "a", number = 1), "zpb.decode.Choice", "number")
  mismatch(list(closed = 5L), "zpb.decode2.Legacy", "closed")
  mismatch(
    list(when = .POSIXct(1e19, tz = "UTC")),
    "zpb.decode.WellKnown",
    "when"
  )
  mismatch(list(depth = 1L, child = "x"), "zpb.decode.Nested", "child")
  mismatch(1:2, "zpb.decode.Point", "")
})

test_that("a missing required field is refused unless check_required = FALSE", {
  pool <- decode_pool()
  expect_error(
    proto_encode(list(name = "x"), "zpb.decode2.Legacy", pool),
    class = "zuproto_missing_required"
  )
  expect_no_error(proto_encode(
    list(name = "x"),
    "zpb.decode2.Legacy",
    pool,
    check_required = FALSE
  ))
})

test_that("unknown fields are written back unless unknown = FALSE", {
  pool <- decode_pool()
  x <- proto_decode(
    msg_fixture("unknown_field"),
    "zpb.decode.Point",
    pool,
    unknown = "keep"
  )
  expect_identical(
    proto_encode(x, "zpb.decode.Point", pool),
    msg_fixture("unknown_field")
  )
  expect_identical(
    proto_encode(x, "zpb.decode.Point", pool, unknown = FALSE),
    as.raw(c(0x08, 0x01))
  )
})

test_that("unusable arguments are invalid arguments, naming the argument", {
  pool <- decode_pool()
  for (arg in c("deterministic", "unknown", "check_required")) {
    args <- list(list(), "zpb.decode.Point", pool)
    args[[arg]] <- NA
    err <- expect_error(
      do.call(proto_encode, args),
      class = "zuproto_invalid_argument"
    )
    expect_identical(err$arg, arg)
  }
  err <- expect_error(
    proto_encode(list(), "zpb.decode.Point", pool, extra = "drop"),
    class = "zuproto_invalid_argument"
  )
  expect_identical(err$arg, "extra")
  expect_error(
    proto_encode(list(), "no.Such", pool),
    class = "zuproto_unknown_type"
  )
})

test_that("NaN encodes in double and float fields, and is refused by integer ones", {
  pool <- decode_pool()
  y <- proto_decode(
    proto_encode(
      list(f_double = NaN, f_float = -Inf),
      "zpb.decode.Scalars",
      pool
    ),
    "zpb.decode.Scalars",
    pool,
    defaults = FALSE
  )
  expect_true(is.nan(y$f_double))
  expect_identical(y$f_float, -Inf)
  expect_error(
    proto_encode(list(f_int32 = NaN), "zpb.decode.Scalars", pool),
    class = "zuproto_type_mismatch"
  )
  expect_identical(
    proto_encode(list(f_double = NA_real_), "zpb.decode.Scalars", pool),
    raw()
  )
})

test_that("a Timestamp the binary format allows round-trips, and JSON refuses it", {
  pool <- proto_pool()
  far <- .POSIXct(9e15, tz = "UTC") # past 9999-12-31
  raw <- proto_encode(far, "google.protobuf.Timestamp", pool)
  expect_identical(
    unclass(proto_decode(raw, "google.protobuf.Timestamp", pool)),
    unclass(far)
  )
  expect_error(
    proto_to_json(raw, "google.protobuf.Timestamp", pool),
    class = "zuproto_json_error"
  )
})

test_that("a value nested far past the limit is a depth limit, not a C stack error", {
  # #88: the R value is walked before upb's encoder counts levels, so the
  # walk stops at the limit itself.
  pool <- decode_pool()
  nested <- list(depth = 1L)
  for (i in seq_len(50000)) {
    nested <- list(child = nested)
  }
  err <- expect_error(
    proto_encode(nested, "zpb.decode.Nested", pool),
    class = "zuproto_depth_limit"
  )
  expect_identical(err$limit, "max_depth")
  value <- 1
  for (i in seq_len(50000)) {
    value <- list(value)
  }
  expect_error(
    proto_encode(value, "google.protobuf.Value", pool),
    class = "zuproto_depth_limit"
  )
})

test_that("encoding nests as deep as decoding allows, then is a depth limit error", {
  # #27: upb's encoder stopped at 100 levels and zuproto called it out of
  # memory. nested(n) is n messages, one inside the next.
  nested <- function(n) {
    x <- list(depth = 1L)
    for (i in seq_len(n - 1)) {
      x <- list(depth = 1L, child = x)
    }
    x
  }
  pool <- decode_pool()
  raw <- proto_encode(nested(1001), "zpb.decode.Nested", pool)
  x <- proto_decode(raw, "zpb.decode.Nested", pool, max_depth = 1000)
  expect_identical(proto_encode(x, "zpb.decode.Nested", pool), raw)
  err <- expect_error(
    proto_encode(nested(1002), "zpb.decode.Nested", pool),
    class = "zuproto_depth_limit"
  )
  expect_s3_class(err, "zuproto_limit_error")
  expect_identical(err$limit, "max_depth")
  expect_identical(err$limit_value, 1000L)
})

test_that("an error code R does not map is a zuproto_internal_error", {
  err <- expect_error(
    encode_error(list(error = "other"), "pkg.M", NULL),
    class = "zuproto_internal_error"
  )
  expect_identical(err$code, "other")
  err <- expect_error(
    decode_error(list(error = "out_of_memory"), "pkg.M", 1, 1, NULL),
    class = "zuproto_internal_error"
  )
  expect_match(conditionMessage(err), "out of memory")
})

test_that("strings that are not valid UTF-8 text are type mismatches", {
  # #29: invalid UTF-8 was written as R's "<ff><fe>" escapes, and a string
  # marked as bytes raised a bare error.
  pool <- decode_pool()
  bad <- "\xff\xfe"
  Encoding(bad) <- "UTF-8"
  bytes <- "abc\xff" # R marks only non-ASCII strings as bytes
  Encoding(bytes) <- "bytes"
  cases <- list(
    list(list(f_string = bad), "zpb.decode.Scalars", "f_string"),
    list(list(f_string = bytes), "zpb.decode.Scalars", "f_string"),
    list(
      list(by_string = stats::setNames(1L, bad)),
      "zpb.decode.Maps",
      "by_string"
    ),
    list(
      list(meta = stats::setNames(list(1), bad)),
      "zpb.decode.WellKnown",
      "meta"
    ),
    list(list(value = bad), "zpb.decode.WellKnown", "value"),
    list(stats::setNames(list("x"), bad), "zpb.decode.Scalars", ""),
    # #89: an enum given as a factor, and a field name marked as bytes.
    list(list(f_enum = factor(bad)), "zpb.decode.Scalars", "f_enum"),
    list(stats::setNames(list("x"), bytes), "zpb.decode.Scalars", "")
  )
  for (i in seq_along(cases)) {
    case <- cases[[i]]
    label <- sprintf("case %d, %s", i, case[[2]])
    err <- expect_error(
      proto_encode(case[[1]], case[[2]], pool),
      class = "zuproto_type_mismatch",
      label = label
    )
    expect_identical(err$path, case[[3]], label = label)
  }
  latin1 <- "caf\xe9"
  Encoding(latin1) <- "latin1"
  raw <- proto_encode(list(f_string = latin1), "zpb.decode.Scalars", pool)
  expect_identical(
    proto_decode(raw, "zpb.decode.Scalars", pool)$f_string,
    "café"
  )
})

test_that("dates and times go only where a Timestamp or Duration is", {
  # #30: a Date was taken as seconds since the epoch.
  pool <- proto_pool()
  date <- as.Date("2026-10-26")
  expect_error(
    proto_encode(date, "google.protobuf.Timestamp", pool),
    class = "zuproto_type_mismatch"
  )
  expect_error(
    proto_encode(
      as.difftime(1, units = "secs"),
      "google.protobuf.Timestamp",
      pool
    ),
    class = "zuproto_type_mismatch"
  )
  expect_error(
    proto_encode(Sys.time(), "google.protobuf.Duration", pool),
    class = "zuproto_type_mismatch"
  )
  expect_error(
    proto_encode(date, "google.protobuf.DoubleValue", pool),
    class = "zuproto_type_mismatch"
  )
  expect_error(
    proto_encode(list(f_double = date), "zpb.decode.Scalars", decode_pool()),
    class = "zuproto_type_mismatch"
  )
  when <- as.POSIXct(date, tz = "UTC")
  raw <- proto_encode(when, "google.protobuf.Timestamp", pool)
  expect_equal(proto_decode(raw, "google.protobuf.Timestamp", pool), when)
})

test_that("a field given twice is a type mismatch", {
  # #31: the last value won, or a repeated field's values were appended.
  pool <- decode_pool()
  err <- expect_error(
    proto_encode(
      list(f_string = "a", f_string = "b"),
      "zpb.decode.Scalars",
      pool
    ),
    class = "zuproto_type_mismatch"
  )
  expect_identical(err$path, "f_string")
  expect_error(
    proto_encode(list(packed = 1:2, packed = 3L), "zpb.decode.Repeated", pool),
    class = "zuproto_type_mismatch"
  )
  expect_error(
    proto_encode(
      list(f_int32 = NULL, f_int32 = 1L),
      "zpb.decode.Scalars",
      pool
    ),
    class = "zuproto_type_mismatch"
  )
})

test_that("every scalar kind of the mapping round-trips its edge values", {
  # #45: one row per kind of design section 6.1, at its edges, built in R.
  pool <- decode_pool()
  type <- "zpb.decode.Scalars"
  imax <- .Machine$integer.max
  edges <- list(
    f_double = c(
      -Inf,
      -.Machine$double.xmax,
      -0,
      2^-1074,
      .Machine$double.xmax,
      Inf
    ),
    # Exact powers of two: R's parser does not round long decimal
    # literals the same way on every platform (macOS arm64 differs).
    f_float = c(-Inf, -(2 - 2^-23) * 2^127, 2^-149, 0.25, Inf),
    f_int32 = c(-imax, -1L, 0L, imax),
    f_sint32 = c(-imax, -1L, 1L, imax),
    f_sfixed32 = c(-imax, -1L, imax),
    f_uint32 = c(0, 1, 2^31, 2^32 - 1),
    f_fixed32 = c(0, 2^31, 2^32 - 1),
    f_int64 = c("-9223372036854775808", "-1", "9223372036854775807"),
    f_sint64 = c("-9223372036854775808", "-1", "1", "9223372036854775807"),
    f_sfixed64 = c("-9223372036854775808", "9223372036854775807"),
    f_uint64 = c("0", "9223372036854775808", "18446744073709551615"),
    f_fixed64 = c("0", "18446744073709551615"),
    f_bool = c(FALSE, TRUE),
    f_string = c("", "a", "é中\U0001f600"),
    f_enum = c("LEVEL_UNSPECIFIED", "HIGH")
  )
  for (field in names(edges)) {
    for (v in edges[[field]]) {
      x <- stats::setNames(list(v), field)
      raw <- proto_encode(x, type, pool)
      y <- proto_decode(
        raw,
        type,
        pool,
        int64 = "character",
        enums = "character"
      )
      expect_identical(y[[field]], v, label = sprintf("%s = %s", field, v))
    }
  }
})
