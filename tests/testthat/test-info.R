test_that("zuproto_info() names the bundled protobuf release", {
  info <- zuproto_info()
  expect_s3_class(info, "zuproto_info")
  expect_identical(info$version, as.character(packageVersion("zuproto")))
  expect_match(info$protobuf, "^v[0-9]+\\.[0-9]+$")
  expect_match(info$protobuf_commit, "^[0-9a-f]{40}$")
  expect_match(format(info)[3], info$protobuf, fixed = TRUE)
  expect_identical(info$limits, list(max_size = 64 * 1024^2, max_depth = 100L))
})

test_that("conditions carry their classes and fields", {
  err <- tryCatch(zpb_invalid_argument("x", "bad"), error = identity)
  expect_s3_class(
    err,
    c("zuproto_invalid_argument", "zuproto_error", "error", "condition"),
    exact = TRUE
  )
  expect_identical(err$arg, "x")
})
