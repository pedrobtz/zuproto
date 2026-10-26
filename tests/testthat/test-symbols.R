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
  # A positive control (#37): the library must import R's API, so a listing
  # without Rf_error means nm listed nothing and the check below would pass
  # vacuously. nm may list no imports of a Windows DLL; that is a skip, said.
  skip_if(
    .Platform$OS.type == "windows" && !"Rf_error" %in% undefined,
    "nm lists no imports of this DLL"
  )
  expect_contains(undefined, "Rf_error")
  expect_equal(intersect(undefined, forbidden), character())
})
