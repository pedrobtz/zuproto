test_that("the package loads its native library", {
  expect_true("zuproto" %in% names(getLoadedDLLs()))
})

test_that("the choices the options check are the signatures' defaults", {
  # #50: zpb_choices is checked against; the signatures show the choices.
  choices <- zuproto:::zpb_choices
  for (f in list(proto_decode, proto_decode_df, proto_read_delimited)) {
    args <- formals(f)
    for (arg in c("int64", "enums", "bytes")) {
      expect_identical(eval(args[[arg]]), choices[[arg]])
    }
  }
  expect_identical(eval(formals(proto_decode)$unknown), choices$unknown)
  expect_identical(eval(formals(proto_to_json)$enums), choices$json_enums)
})
