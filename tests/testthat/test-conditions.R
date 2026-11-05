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
    proto_pool(file("no/such/file.binpb"))
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
  bad <- "\xff\xfe"
  Encoding(bad) <- "UTF-8"
  expect_snapshot(error = TRUE, {
    proto_encode(list(f_enum = factor(bad)), "zpb.decode.Scalars", pool)
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
    zuproto:::decode_error(list(error = "arena_limit"), "pkg.M", 1e6, 100, NULL)
    zuproto:::decode_error(
      list(error = "frame_too_long", field = "pkg.M.items"),
      "pkg.M",
      1e6,
      100,
      NULL
    )
    proto_encode(as.Date("2026-01-01"), "google.protobuf.Value", pool)
    proto_encode(c(a = 1), "google.protobuf.Value", pool)
    proto_encode(list(f_int32 = sum), "zpb.decode.Scalars", pool)
    proto_encode(list(f_uint64 = " -1"), "zpb.decode.Scalars", pool)
    proto_write_delimited(list(), "zpb.decode.Point", pool, determinstic = TRUE)
    proto_write_delimited(
      list(list(x = 1L)),
      "zpb.decode.Point",
      pool,
      path = "no/such/dir/x.bin"
    )
  })
})

test_that("a string the native encoding cannot read is described", {
  pool <- decode_pool()
  withr::local_locale(c(LC_CTYPE = "C"))
  x <- rawToChar(as.raw(c(0x61, 0xff)))
  expect_snapshot(error = TRUE, {
    proto_encode(list(f_string = x), "zpb.decode.Scalars", pool)
    proto_from_json(x, "zpb.decode.Scalars", pool)
  })
})

test_that("JSON errors read well", {
  pool <- decode_pool()
  bad <- rawToChar(as.raw(c(charToRaw('{"f_string":"'), 0xff, charToRaw('"}'))))
  Encoding(bad) <- "UTF-8"
  bytes <- bad
  Encoding(bytes) <- "bytes"
  expect_snapshot(error = TRUE, {
    proto_from_json('{"f_int32": "x"}', "zpb.decode.Scalars", pool)
    proto_pack_any(list(), "zpb.decode.Point", pool, prefix = "x.io")
    proto_pack_any(list(), "zpb.decode.Point", pool, foo = 1)
    proto_unpack_any(list(type_url = "x", value = raw()), pool)
    proto_from_json(bad, "zpb.decode.Scalars", pool)
    proto_from_json(bytes, "zpb.decode.Scalars", pool)
  })
})

test_that("warnings read well", {
  pool <- decode_pool()
  low <- proto_pool(proto_encode(
    list(
      file = list(list(
        name = "low.proto",
        package = "low",
        syntax = "proto3",
        enum_type = list(list(
          name = "E",
          value = list(
            list(name = "Z", number = 0L),
            list(name = "LOW", number = -2^31)
          )
        ))
      ))
    ),
    "google.protobuf.FileDescriptorSet",
    proto_pool()
  ))
  raw <- c(as.raw(0x80), as.raw(0x01), as.raw(5)) # f_enum = 5
  expect_snapshot({
    x <- proto_decode(msg_fixture("scalars_big"), "zpb.decode.Scalars", pool)
    x <- proto_decode(raw, "zpb.decode.Scalars", pool)
    x <- proto_enums(low, "low.E")
  })
})
