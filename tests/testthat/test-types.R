test_that("proto_types() lists nested types, not map entries, sorted", {
  types <- proto_types(fixture_pool("schema"))
  expect_named(types, c("name", "file", "fields"))
  expect_false(is.unsorted(types$name, strictly = TRUE))
  holder <- types[types$name == "zpb.test.Holder", ]
  expect_identical(holder$file, "schema.proto")
  expect_identical(holder$fields, 4L)
  expect_true("zpb.test.Holder.Inner" %in% types$name)
  expect_false(any(grepl("CountsEntry", types$name)))
})

test_that("proto_fields() describes each kind of field", {
  f <- proto_fields(fixture_pool("schema"), "zpb.test.Scalars")
  expect_named(
    f,
    c(
      "name",
      "number",
      "type",
      "label",
      "type_name",
      "oneof",
      "json_name",
      "presence",
      "packed",
      "map",
      "extension"
    )
  )
  row <- function(name) f[f$name == name, ]

  expect_identical(row("f_double")$type, "double")
  expect_identical(row("f_sint64")$type, "sint64")
  expect_identical(row("f_bytes")$type, "bytes")
  expect_identical(row("f_string")$json_name, "fString")
  expect_identical(row("f_string")$presence, FALSE)
  expect_identical(row("f_optional")$presence, TRUE)
  expect_identical(row("f_optional")$oneof, NA_character_)
  expect_identical(row("f_packed")$label, "repeated")
  expect_identical(row("f_packed")$packed, TRUE)
  expect_identical(row("color")$type, "enum")
  expect_identical(row("color")$type_name, "zpb.test.Color")
  expect_identical(row("when")$type, "message")
  expect_identical(row("when")$type_name, "google.protobuf.Timestamp")
  expect_identical(row("when")$number, 12L)
})

test_that("proto_fields() reports maps and oneofs", {
  f <- proto_fields(fixture_pool("schema"), "zpb.test.Holder")
  expect_identical(f$map[f$name == "counts"], TRUE)
  expect_identical(f$label[f$name == "inners"], "repeated")
  expect_identical(
    f$oneof[f$name %in% c("text", "number")],
    c("choice", "choice")
  )
})

test_that("proto_fields() lists extensions under bracketed full names", {
  f <- proto_fields(fixture_pool("legacy"), "zpb.legacy.Base")
  expect_identical(f$name, c("id", "note", "[zpb.legacy.tag]"))
  expect_identical(f$extension, c(FALSE, FALSE, TRUE))
  expect_identical(f$number[3], 100L)
  expect_identical(f$label[1], "required")
})

test_that("an unknown type is a zuproto_unknown_type error", {
  err <- expect_error(
    proto_fields(proto_pool(), "no.such.Type"),
    class = "zuproto_unknown_type"
  )
  expect_identical(err$type, "no.such.Type")
})

test_that("a type that is not a single string is an invalid argument", {
  pool <- proto_pool()
  for (bad in list(NULL, NA_character_, "", c("a", "b"), 1)) {
    err <- expect_error(
      proto_fields(pool, bad),
      class = "zuproto_invalid_argument"
    )
    expect_identical(err$arg, "type")
  }
})

test_that("proto_enums() lists an enum's values in definition order", {
  pool <- fixture_pool("schema")
  e <- proto_enums(pool, "zpb.test.Color")
  expect_identical(
    e,
    data.frame(
      name = c("COLOR_UNSPECIFIED", "RED", "GREEN"),
      number = 0:2
    )
  )
  # The enum proto_fields() names for a field.
  f <- proto_fields(pool, "zpb.test.Scalars")
  expect_identical(
    nrow(proto_enums(pool, f$type_name[f$name == "color"])),
    3L
  )
  expect_identical(
    proto_enums(proto_pool(), "google.protobuf.NullValue")$name,
    "NULL_VALUE"
  )
})

test_that("proto_enums() refuses a name that is not an enum in the pool", {
  pool <- fixture_pool("schema")
  err <- expect_error(
    proto_enums(pool, "zpb.test.Nope"),
    class = "zuproto_unknown_type"
  )
  expect_identical(err$type, "zpb.test.Nope")
  # A message type is not an enum.
  expect_error(
    proto_enums(pool, "zpb.test.Scalars"),
    class = "zuproto_unknown_type"
  )
  expect_error(proto_enums(pool, NA), class = "zuproto_invalid_argument")
  expect_error(proto_enums(list(), "x"), class = "zuproto_invalid_argument")
})
