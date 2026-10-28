test_that("binary converts to protobuf JSON and back", {
  pool <- decode_pool()
  types <- fixture_types()
  for (name in setdiff(names(types), c("unknown_field", "scalars_big"))) {
    raw <- msg_fixture(name)
    json <- proto_to_json(raw, types[[name]], pool)
    expect_type(json, "character")
    expect_identical(
      proto_from_json(json, types[[name]], pool),
      raw,
      label = name
    )
  }
})

test_that("JSON uses the canonical mapping", {
  pool <- decode_pool()
  json <- proto_to_json(msg_fixture("scalars_set"), "zpb.decode.Scalars", pool)
  expect_match(json, '"fInt64":"-1234567890123"', fixed = TRUE)
  expect_match(json, '"fEnum":"HIGH"', fixed = TRUE)
  expect_match(json, '"fBytes":"AAEC/w=="', fixed = TRUE)
  expect_match(
    proto_to_json(
      msg_fixture("scalars_set"),
      "zpb.decode.Scalars",
      pool,
      proto_names = TRUE,
      enums = "integer"
    ),
    '"f_enum":2',
    fixed = TRUE
  )
  expect_identical(proto_to_json(raw(), "zpb.decode.Point", pool), "{}")
  expect_identical(
    proto_to_json(raw(), "zpb.decode.Point", pool, emit_defaults = TRUE),
    '{"x":0,"y":0}'
  )
  wk <- proto_to_json(msg_fixture("wellknown"), "zpb.decode.WellKnown", pool)
  expect_match(wk, '"when":"2026-10-25T12:34:56.123456789Z"', fixed = TRUE)
  expect_match(wk, '"took":"90.500s"', fixed = TRUE)
  expect_match(
    wk,
    '"@type":"type.googleapis.com/zpb.decode.Point"',
    fixed = TRUE
  )
})

test_that("JSON that is not the type's is a zuproto_json_error", {
  pool <- decode_pool()
  expect_error(
    proto_from_json("{", "zpb.decode.Point", pool),
    class = "zuproto_json_error"
  )
  expect_error(
    proto_from_json('{"x":"a"}', "zpb.decode.Point", pool),
    class = "zuproto_json_error"
  )
  expect_error(
    proto_from_json('{"nope":1}', "zpb.decode.Point", pool),
    class = "zuproto_json_error"
  )
  expect_identical(
    proto_from_json(
      '{"x":1,"nope":1}',
      "zpb.decode.Point",
      pool,
      ignore_unknown = TRUE
    ),
    as.raw(c(0x08, 0x01))
  )
  expect_error(
    proto_from_json('{"name":"x"}', "zpb.decode2.Legacy", pool),
    class = "zuproto_missing_required"
  )
  expect_error(
    proto_from_json("{}", "zpb.decode.Point", pool, max_size = 1),
    class = "zuproto_size_limit"
  )
  expect_error(
    proto_to_json(as.raw(0xff), "zpb.decode.Point", pool),
    class = "zuproto_parse_error"
  )
})

test_that("JSON meets R values through zujson", {
  skip_if_not_installed("zujson")
  pool <- decode_pool()
  raw <- msg_fixture("repeated")
  parsed <- proto_to_json(raw, "zpb.decode.Repeated", pool, parse = TRUE)
  expect_identical(parsed$strings, c("a", "b"))
  expect_identical(proto_from_json(parsed, "zpb.decode.Repeated", pool), raw)
  # A repeated field of one element needs I() to stay a JSON array.
  one <- proto_from_json(list(packed = I(7L)), "zpb.decode.Repeated", pool)
  expect_identical(proto_decode(one, "zpb.decode.Repeated", pool)$packed, 7L)
})

test_that("unusable JSON arguments are invalid arguments", {
  pool <- decode_pool()
  expect_error(
    proto_from_json(NA_character_, "zpb.decode.Point", pool),
    class = "zuproto_invalid_argument"
  )
  err <- expect_error(
    proto_to_json(raw(), "zpb.decode.Point", pool, enums = "factor"),
    class = "zuproto_invalid_argument"
  )
  expect_identical(err$arg, "enums")
})

test_that("proto_unpack_any() decodes the packed message", {
  pool <- decode_pool()
  wk <- proto_decode(msg_fixture("wellknown"), "zpb.decode.WellKnown", pool)
  expect_identical(proto_unpack_any(wk$any, pool), list(x = 1L, y = 2L))
  expect_error(
    proto_unpack_any(
      list(type_url = "type.googleapis.com/no.Such", value = raw()),
      pool
    ),
    class = "zuproto_unknown_type"
  )
  expect_error(
    proto_unpack_any(list(value = raw()), pool),
    class = "zuproto_invalid_argument"
  )
  # #38: `type` in ... would shift proto_decode()'s arguments.
  err <- expect_error(
    proto_unpack_any(wk$any, pool, type = "zpb.decode.Point"),
    class = "zuproto_invalid_argument"
  )
  expect_identical(err$arg, "type")
  expect_identical(
    proto_unpack_any(wk$any, pool, defaults = FALSE),
    list(x = 1L, y = 2L)
  )
})

test_that("int64 = \"integer64\" decodes 64-bit fields exactly", {
  skip_if_not_installed("bit64")
  pool <- decode_pool()
  x <- proto_decode(
    msg_fixture("scalars_set"),
    "zpb.decode.Scalars",
    pool,
    int64 = "integer64"
  )
  expect_s3_class(x$f_int64, "integer64")
  expect_identical(as.character(x$f_int64), "-1234567890123")
  expect_identical(as.character(x$f_uint64), "9007199254740992")

  w <- expect_warning(
    big <- proto_decode(
      msg_fixture("scalars_big"),
      "zpb.decode.Scalars",
      pool,
      int64 = "integer64"
    ),
    class = "zuproto_precision_loss"
  )
  expect_identical(as.character(big$f_int64), "9223372036854775807")
  expect_true(bit64::is.na.integer64(big$f_uint64)) # above 2^63 - 1
  expect_identical(w$n, 3) # f_uint64 and the two int32 -2^31 values

  df <- proto_decode_df(
    list(msg_fixture("scalars_set"), msg_fixture("scalars_empty")),
    "zpb.decode.Scalars",
    pool,
    int64 = "integer64",
    defaults = FALSE
  )
  expect_s3_class(df$f_int64, "integer64")
  expect_identical(as.character(df$f_int64), c("-1234567890123", NA))
})

test_that("integer64 values encode exactly", {
  skip_if_not_installed("bit64")
  pool <- decode_pool()
  x <- list(
    f_int64 = bit64::as.integer64("-9223372036854775807"),
    f_uint64 = bit64::as.integer64("42"),
    f_int32 = bit64::as.integer64(7)
  )
  y <- proto_decode(
    proto_encode(x, "zpb.decode.Scalars", pool),
    "zpb.decode.Scalars",
    pool,
    int64 = "character",
    defaults = FALSE
  )
  expect_identical(y$f_int64, "-9223372036854775807")
  expect_identical(y$f_uint64, "42")
  expect_identical(y$f_int32, 7L)
  expect_identical(
    proto_encode(
      list(f_int64 = bit64::NA_integer64_),
      "zpb.decode.Scalars",
      pool
    ),
    raw()
  )
  expect_error(
    proto_encode(
      list(f_uint64 = bit64::as.integer64(-1)),
      "zpb.decode.Scalars",
      pool
    ),
    class = "zuproto_type_mismatch"
  )
})

test_that("Timestamp and Duration nanos out of range are refused in JSON", {
  pool <- proto_pool()
  # Duration{nanos = -2^31} and Timestamp{nanos = -1}, which binary allows.
  # -2^31 as a 10-byte varint, written out: varint() works in doubles and
  # warns at 2^64 on some platforms.
  dur <- c(
    as.raw(0x10),
    as.raw(c(0x80, 0x80, 0x80, 0x80, 0xf8, rep(0xff, 4), 0x01))
  )
  ts <- c(as.raw(0x10), as.raw(c(rep(0xff, 9), 0x01))) # -1 as a 10-byte varint
  expect_error(
    proto_to_json(dur, "google.protobuf.Duration", pool),
    class = "zuproto_json_error"
  )
  expect_error(
    proto_to_json(ts, "google.protobuf.Timestamp", pool),
    class = "zuproto_json_error"
  )
})

test_that("nested Anys are bounded by max_depth before upb's JSON encoder sees them", {
  # #25: upb's JSON encoder decodes each packed Any afresh, unbounded; a chain
  # of Anys must fail as a depth limit, not overflow the C stack.
  pool <- proto_pool()
  any <- function(type, value) {
    url <- charToRaw(paste0("type.googleapis.com/google.protobuf.", type))
    c(
      as.raw(0x0a),
      varint(length(url)),
      url,
      as.raw(0x12),
      varint(length(value)),
      value
    )
  }
  chain <- function(n) {
    out <- any("Duration", as.raw(c(0x08, 0x01))) # 1s
    for (i in seq_len(n)) {
      out <- any("Any", out)
    }
    out
  }
  deep <- chain(2000)
  expect_no_error(proto_decode(deep, "google.protobuf.Any", pool))
  err <- expect_error(
    proto_to_json(deep, "google.protobuf.Any", pool),
    class = "zuproto_depth_limit"
  )
  expect_identical(err$limit, "max_depth")
  expect_match(
    proto_to_json(chain(5), "google.protobuf.Any", pool),
    '"1s"',
    fixed = TRUE
  )
})

test_that("JSON nested past upb's parser limit is a JSON error", {
  # #48: upb's JSON parser stops at 64 levels, below the encoder's 1000, so
  # proto_from_json() never reaches the encoder's depth limit.
  pool <- decode_pool()
  json <- function(n) {
    paste0(strrep('{"child":', n - 1), '{"depth":1}', strrep("}", n - 1))
  }
  expect_type(proto_from_json(json(60), "zpb.decode.Nested", pool), "raw")
  expect_error(
    proto_from_json(json(100), "zpb.decode.Nested", pool),
    class = "zuproto_json_error"
  )
})

test_that("proto_pack_any() is the inverse of proto_unpack_any()", {
  pool <- decode_pool()
  any <- proto_pack_any(list(x = 1L, y = 2L), "zpb.decode.Point", pool)
  expect_identical(
    any,
    list(
      type_url = "type.googleapis.com/zpb.decode.Point",
      value = proto_encode(list(x = 1L, y = 2L), "zpb.decode.Point", pool)
    )
  )
  expect_identical(proto_unpack_any(any, pool), list(x = 1L, y = 2L))

  # It sets an Any field: the same bytes as Python's fixture.
  wk <- proto_decode(msg_fixture("wellknown"), "zpb.decode.WellKnown", pool)
  expect_identical(
    proto_pack_any(proto_unpack_any(wk$any, pool), "zpb.decode.Point", pool),
    wk$any
  )
  raw <- proto_encode(
    list(any = proto_pack_any(list(x = 1L), "zpb.decode.Point", pool)),
    "zpb.decode.WellKnown",
    pool
  )
  expect_match(
    proto_to_json(raw, "zpb.decode.WellKnown", pool),
    '"any":{"@type":"type.googleapis.com/zpb.decode.Point","x":1}',
    fixed = TRUE
  )
})

test_that("proto_pack_any() checks its arguments as proto_encode() does", {
  pool <- decode_pool()
  expect_error(
    proto_pack_any(list(), "no.Such", pool),
    class = "zuproto_unknown_type"
  )
  expect_error(
    proto_pack_any(list(nope = 1), "zpb.decode.Point", pool),
    class = "zuproto_unknown_field"
  )
  err <- expect_error(
    proto_pack_any(list(), "zpb.decode.Point", pool, prefix = NA),
    class = "zuproto_invalid_argument"
  )
  expect_identical(err$arg, "prefix")
  expect_identical(
    proto_pack_any(list(), "zpb.decode.Point", pool, prefix = "x.io/")$type_url,
    "x.io/zpb.decode.Point"
  )
})
