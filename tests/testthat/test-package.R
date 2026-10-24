test_that("the package loads its native library", {
  expect_true("zuproto" %in% names(getLoadedDLLs()))
})
