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
