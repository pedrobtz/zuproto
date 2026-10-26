test_that("a new pool holds every well-known type", {
  pool <- proto_pool()
  wkt <- c(
    "google.protobuf.Any",
    "google.protobuf.Api",
    "google.protobuf.BoolValue",
    "google.protobuf.Duration",
    "google.protobuf.Empty",
    "google.protobuf.FieldMask",
    "google.protobuf.FileDescriptorSet",
    "google.protobuf.ListValue",
    "google.protobuf.SourceContext",
    "google.protobuf.Struct",
    "google.protobuf.Timestamp",
    "google.protobuf.Type",
    "google.protobuf.Value"
  )
  expect_true(all(wkt %in% proto_types(pool)$name))
  expect_setequal(
    unique(proto_types(pool)$file),
    paste0(
      "google/protobuf/",
      c(
        "any",
        "api",
        "descriptor",
        "duration",
        "empty",
        "field_mask",
        "source_context",
        "struct",
        "timestamp",
        "type",
        "wrappers"
      ),
      ".proto"
    )
  )
})

test_that("a schema's set loads from raw, a path and a connection", {
  path <- test_path("fixtures", "schema.binpb")

  from_raw <- proto_pool(fixture("schema"))
  from_path <- proto_pool(path)
  con <- file(path, "rb")
  on.exit(close(con))
  from_con <- proto_pool(con)

  for (pool in list(from_raw, from_path, from_con)) {
    expect_true(all(
      c("zpb.test.Scalars", "zpb.test.Holder", "zpb.test.Holder.Inner") %in%
        proto_types(pool)$name
    ))
  }
})

test_that("proto_pool_add() adds to the pool it is given", {
  pool <- proto_pool()
  expect_identical(proto_pool_add(pool, fixture("legacy")), pool)
  expect_true("zpb.legacy.Base" %in% proto_types(pool)$name)
})

test_that("a set listing a file before its import loads in dependency order", {
  reversed <- c(fixture("uses_dep"), fixture("dep"))
  pool <- proto_pool(reversed)
  expect_true(all(
    c("zpb.dep.Leaf", "zpb.uses.Branch") %in% proto_types(pool)$name
  ))
})

test_that("a missing import names the file and the import, and adds nothing", {
  pool <- proto_pool()
  before <- proto_types(pool)
  err <- expect_error(
    proto_pool_add(pool, fixture("uses_dep")),
    class = "zuproto_pool_error"
  )
  expect_identical(err$file, "uses_dep.proto")
  expect_identical(err$missing, "dep.proto")
  expect_identical(proto_types(pool), before)
})

test_that("re-adding an identical file is a no-op", {
  pool <- proto_pool(fixture("dep"))
  before <- proto_types(pool)
  expect_no_error(proto_pool_add(pool, fixture("dep")))
  expect_identical(proto_types(pool), before)
})

test_that("a set including a well-known type the pool already has loads", {
  pool <- proto_pool(fixture("all"))
  expect_true(all(
    c("zpb.test.Scalars", "zpb.legacy.Base", "zpb.editions.Thing") %in%
      proto_types(pool)$name
  ))
})

test_that("a different file of the same name is a conflict", {
  pool <- proto_pool(fixture("dep"))
  err <- expect_error(
    proto_pool_add(pool, fixture("dep_v2")),
    class = "zuproto_pool_conflict"
  )
  expect_s3_class(err, "zuproto_pool_error")
  expect_identical(err$file, "dep.proto")

  err <- expect_error(
    proto_pool(c(fixture("dep"), fixture("dep_v2"))),
    class = "zuproto_pool_conflict"
  )
  expect_identical(err$file, "dep.proto")
})

test_that("an editions file loads", {
  pool <- proto_pool(fixture("editions"))
  expect_identical(
    proto_fields(pool, "zpb.editions.Thing")$name,
    c("x", "label")
  )
})

test_that("empty input adds nothing", {
  pool <- proto_pool()
  before <- proto_types(pool)
  expect_no_error(proto_pool_add(pool, raw()))
  expect_identical(proto_types(pool), before)
})

test_that("bytes that are not a descriptor set are a pool error", {
  expect_error(
    proto_pool(as.raw(c(0x0a, 0xff, 0xff))),
    class = "zuproto_pool_error"
  )
  expect_error(
    proto_pool(charToRaw("not protobuf at all")),
    class = "zuproto_pool_error"
  )
})

test_that("unusable inputs fail with classed errors", {
  expect_error(proto_pool(tempfile()), class = "zuproto_io_error")
  expect_error(proto_pool(42), class = "zuproto_invalid_argument")
  expect_error(
    proto_pool_add(list(), raw()),
    class = "zuproto_invalid_argument"
  )
})

test_that("a pool restored by readRDS() is an invalid argument, not a crash", {
  skip_if_not_installed("withr")
  path <- withr::local_tempfile(fileext = ".rds")
  saveRDS(proto_pool(), path)
  stale <- readRDS(path)
  err <- expect_error(proto_types(stale), class = "zuproto_invalid_argument")
  expect_identical(err$arg, "pool")
  expect_match(format(stale), "invalid")
})

test_that("a pool prints its size", {
  expect_match(
    format(proto_pool()),
    "^<proto_pool: 11 files, [0-9]+ message types>$"
  )
})
