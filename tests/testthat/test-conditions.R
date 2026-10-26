# The wording of every condition and warning class (#33). Tests elsewhere
# assert the classes and fields; these snapshots are where a message's
# wording is reviewed, so a wrong figure or a misleading cause shows in the
# diff.

test_that("argument and pool errors read well", {
  expect_snapshot(error = TRUE, {
    proto_decode(raw(), "google.protobuf.Empty", "pool")
    proto_pool("no/such/file.binpb")
    proto_pool_add(proto_pool(), fixture("uses_dep"))
    proto_pool_add(proto_pool(fixture("dep")), fixture("dep_v2"))
    proto_decode(raw(), "no.such.Type", proto_pool())
  })
})

test_that("decoding errors read well", {
  pool <- decode_pool()
  bad <- as.raw(c(0xc3, 0x28))
  nested <- as.raw(c(0x08, 0x01, 0x12, 0x02, 0x08, 0x01))
  expect_snapshot(error = TRUE, {
    proto_decode(as.raw(0x0a), "zpb.decode.Scalars", pool)
    proto_decode(c(as.raw(0x72), varint(2), bad), "zpb.decode.Scalars", pool)
    proto_decode(as.raw(c(0x72, 0x01, 0x00)), "zpb.decode.Scalars", pool)
    proto_decode(
      c(as.raw(c(0x08, 0x01, 0x12, 0x06)), nested),
      "zpb.decode.Nested",
      pool,
      max_depth = 1
    )
    proto_decode(
      msg_fixture("scalars_set"),
      "zpb.decode.Scalars",
      pool,
      max_size = 10
    )
    proto_decode_df(
      rep(list(nested), 3),
      "zpb.decode.Nested",
      pool,
      max_rows = 2
    )
  })
})

test_that("encoding errors read well", {
  pool <- decode_pool()
  deep <- list(depth = 1L)
  for (i in 1:1001) {
    deep <- list(child = deep)
  }
  expect_snapshot(error = TRUE, {
    proto_encode(list(f_int32 = 1.5), "zpb.decode.Scalars", pool)
    proto_encode(
      list(points = list(list(x = "a"))),
      "zpb.decode.Repeated",
      pool
    )
    proto_encode(list(nope = 1), "zpb.decode.Scalars", pool)
    proto_encode(list(name = "x"), "zpb.decode2.Legacy", pool)
    proto_encode(deep, "zpb.decode.Nested", pool)
    zuproto:::encode_error(list(error = "other"), "pkg.M", NULL)
    zuproto:::decode_error(list(error = "out_of_memory"), "pkg.M", 1, 1, NULL)
  })
})

test_that("JSON errors read well", {
  pool <- decode_pool()
  expect_snapshot(error = TRUE, {
    proto_from_json('{"f_int32": "x"}', "zpb.decode.Scalars", pool)
  })
})

test_that("warnings read well", {
  pool <- decode_pool()
  raw <- c(as.raw(0x80), as.raw(0x01), as.raw(5)) # f_enum = 5
  expect_snapshot({
    x <- proto_decode(msg_fixture("scalars_big"), "zpb.decode.Scalars", pool)
    x <- proto_decode(raw, "zpb.decode.Scalars", pool)
  })
})
