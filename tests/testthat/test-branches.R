# C branches reachable from R that the feature tests do not take (#34):
# each is a place where a regression would otherwise pass the suite.

test_that("a stream length prefix longer than a varint can be is malformed", {
  stream <- as.raw(c(rep(0xff, 10), 0x01))
  err <- expect_error(
    proto_read_delimited(stream, "zpb.decode.Nested", decode_pool()),
    class = "zuproto_parse_error"
  )
  expect_identical(err$status, "malformed")
})

test_that("a NUL in a string is unrepresentable in a frame and in a map key", {
  pool <- decode_pool()
  nul <- as.raw(c(0x61, 0x00, 0x62)) # "a\0b"
  in_string <- c(as.raw(0x72), varint(3), nul) # Scalars.f_string
  err <- expect_error(
    proto_decode_df(list(in_string), "zpb.decode.Scalars", pool),
    class = "zuproto_unrepresentable"
  )
  expect_identical(err$field, "zpb.decode.Scalars.f_string")
  entry <- c(as.raw(0x0a), varint(3), nul, as.raw(c(0x10, 0x01)))
  in_key <- c(as.raw(0x0a), varint(length(entry)), entry) # Maps.by_string
  expect_error(
    proto_decode(in_key, "zpb.decode.Maps", pool),
    class = "zuproto_unrepresentable"
  )
})

test_that("uint64 map keys sort and print unsigned, past 2^63", {
  pool <- decode_pool()
  raw <- msg_fixture("uint64_keys")
  expected <- c(
    "1" = "one",
    "9223372036854775808" = "2^63",
    "18446744073709551615" = "max"
  )
  x <- proto_decode(raw, "zpb.decode.Uint64Keys", pool)
  expect_identical(x$by_uint64, expected)
  df <- proto_decode_df(list(raw), "zpb.decode.Uint64Keys", pool)
  expect_identical(df$by_uint64[[1]], expected)
  expect_identical(proto_encode(x, "zpb.decode.Uint64Keys", pool), raw)
})

test_that("a string key sorts before the keys it is a prefix of", {
  pool <- decode_pool()
  raw <- proto_encode(
    list(by_string = c(ab = 1L, a = 2L)),
    "zpb.decode.Maps",
    pool
  )
  x <- proto_decode(raw, "zpb.decode.Maps", pool)
  expect_identical(x$by_string, c(a = 2L, ab = 1L))
})

test_that("a double encodes into a uint64 field when whole and in range", {
  pool <- decode_pool()
  raw <- proto_encode(list(f_uint64 = 5), "zpb.decode.Scalars", pool)
  expect_identical(proto_decode(raw, "zpb.decode.Scalars", pool)$f_uint64, 5)
  for (bad in list(-1, 2^64, 1.5)) {
    expect_error(
      proto_encode(list(f_uint64 = bad), "zpb.decode.Scalars", pool),
      class = "zuproto_type_mismatch"
    )
  }
})

test_that("difftime units convert, and nanos that round up carry a second", {
  pool <- proto_pool()
  seconds <- function(x, type) {
    as.numeric(proto_decode(proto_encode(x, type, pool), type, pool))
  }
  duration <- "google.protobuf.Duration"
  expect_identical(seconds(as.difftime(1.5, units = "mins"), duration), 90)
  expect_identical(seconds(as.difftime(1.5, units = "hours"), duration), 5400)
  expect_identical(seconds(as.difftime(2, units = "days"), duration), 172800)
  expect_identical(seconds(as.difftime(1, units = "weeks"), duration), 604800)
  expect_identical(seconds(-1.9999999999, duration), -2)
  when <- .POSIXct(1.9999999999, tz = "UTC")
  expect_identical(seconds(when, "google.protobuf.Timestamp"), 2)
})

test_that("a ListValue encodes from logical, integer and character vectors", {
  pool <- proto_pool()
  type <- "google.protobuf.ListValue"
  round_trip <- function(x) {
    proto_decode(proto_encode(x, type, pool), type, pool)
  }
  expect_identical(round_trip(c(TRUE, FALSE)), list(TRUE, FALSE))
  expect_identical(round_trip(1:2), list(1, 2))
  expect_identical(round_trip(c("a", "b")), list("a", "b"))
})
