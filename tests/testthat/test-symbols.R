test_that("the shared object links no symbol CRAN's compiled-code check rejects", {
  skip_on_cran()
  # devtools::load_all() compiles with -UNDEBUG, which brings assert() and
  # upb's unreachable-failure path back; only an R CMD INSTALL build counts.
  skip_if(
    exists(".__DEVTOOLS__", envir = asNamespace("zuproto"), inherits = FALSE),
    "debug build from devtools::load_all()"
  )
  # covr's gcov instrumentation links abort, exit and stderr itself.
  skip_if(identical(Sys.getenv("R_COVR"), "true"), "instrumented by covr")
  nm <- Sys.which("nm")
  skip_if(!nzchar(nm), "nm is not available")
  so <- getLoadedDLLs()[["zuproto"]][["path"]]
  undefined <- system2(nm, c("-u", shQuote(so)), stdout = TRUE)
  undefined <- sub("^_", "", trimws(sub("^\\s*U\\s+", "", undefined)))
  undefined <- sub("@.*$", "", undefined)
  forbidden <- c(
    "abort",
    "exit",
    "_exit",
    "printf",
    "puts",
    "putchar",
    "fprintf",
    "vprintf",
    "sprintf",
    "vsprintf",
    "stdout",
    "stderr",
    "__stdoutp",
    "__stderrp",
    "rand",
    "srand",
    "random",
    "srandom",
    "assert",
    "__assert_fail",
    "__assert_rtn"
  )
  expect_equal(intersect(undefined, forbidden), character())
})
