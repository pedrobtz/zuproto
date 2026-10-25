test_that("the vendored upb builds a symbol table", {
  expect_true(.Call(zpb_probe))
})
