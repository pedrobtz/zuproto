# testthat is in Suggests: the nosuggests check runs without it.
if (requireNamespace("testthat", quietly = TRUE)) {
  library(testthat)
  library(zuproto)

  test_check("zuproto")
}
