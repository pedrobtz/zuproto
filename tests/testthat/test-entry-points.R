# What every entry point must do alike: refuse a pool or type it cannot
# use, name a type the pool lacks, and stop at max_depth. Each entry point
# has its own fast path in R and its own branch in C (#32, #36).
# entry_points() is in helper-entry-points.R.

test_that("every entry point refuses a pool it cannot use", {
  stale <- unserialize(serialize(proto_pool(), NULL)) # its pointer is NULL
  for (name in names(entry_points())) {
    f <- entry_points()[[name]]
    expect_no_error(f("google.protobuf.Empty", proto_pool()))
    for (pool in list(stale, "pool", NULL)) {
      err <- expect_error(
        f("google.protobuf.Empty", pool),
        class = "zuproto_invalid_argument",
        label = name
      )
      expect_identical(err$arg, "pool", label = name)
    }
  }
})

test_that("every entry point refuses a type that is not a single name", {
  pool <- proto_pool()
  for (name in names(entry_points())) {
    f <- entry_points()[[name]]
    for (type in list(NA_character_, "", 1, c("a", "b"))) {
      err <- expect_error(
        f(type, pool),
        class = "zuproto_invalid_argument",
        label = name
      )
      expect_identical(err$arg, "type", label = name)
    }
  }
})

test_that("every entry point names a type the pool lacks", {
  pool <- proto_pool()
  for (name in names(entry_points())) {
    err <- expect_error(
      entry_points()[[name]]("no.such.Type", pool),
      class = "zuproto_unknown_type",
      label = name
    )
    expect_identical(err$type, "no.such.Type", label = name)
  }
})

test_that("every decoding entry point stops at max_depth", {
  pool <- decode_pool()
  nested <- as.raw(c(0x08, 0x01))
  for (i in 1:10) {
    nested <- c(as.raw(c(0x08, 0x01, 0x12)), varint(length(nested)), nested)
  }
  type <- "zpb.decode.Nested"
  calls <- list(
    proto_decode = function(d) proto_decode(nested, type, pool, max_depth = d),
    proto_decode_df = function(d) {
      proto_decode_df(list(nested), type, pool, max_depth = d)
    },
    proto_read_delimited = function(d) {
      stream <- c(varint(length(nested)), nested)
      proto_read_delimited(stream, type, pool, max_depth = d)
    },
    proto_to_json = function(d) proto_to_json(nested, type, pool, max_depth = d)
  )
  for (name in names(calls)) {
    expect_no_error(calls[[name]](10))
    err <- expect_error(
      calls[[name]](9),
      class = "zuproto_depth_limit",
      label = name
    )
    expect_identical(err$limit, "max_depth", label = name)
    expect_identical(err$limit_value, 9, label = name)
  }
})

test_that("C's own failures are zuproto_internal_error, not bare errors", {
  # #40: reached only past R's argument checks, so called directly here.
  err <- expect_error(
    .Call(zuproto:::zpb_pool_types, NULL, TRUE),
    class = "zuproto_internal_error"
  )
  expect_match(conditionMessage(err), "not a pool pointer")
})
