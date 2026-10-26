test_that("every scalar type decodes as design section 6.1 maps it", {
  x <- proto_decode(
    msg_fixture("scalars_set"),
    "zpb.decode.Scalars",
    decode_pool()
  )
  expect_identical(
    x,
    list(
      f_double = 1.5,
      f_float = 0.25,
      f_int32 = -42L,
      f_sint32 = -7L,
      f_sfixed32 = 123L,
      f_uint32 = 4e9,
      f_fixed32 = 3e9,
      f_int64 = -1234567890123,
      f_uint64 = 2^53,
      f_sint64 = -5,
      f_fixed64 = 1,
      f_sfixed64 = -2,
      f_bool = TRUE,
      f_string = "héllo ✓",
      f_bytes = as.raw(c(0x00, 0x01, 0x02, 0xff)),
      f_enum = factor("HIGH", levels = c("LEVEL_UNSPECIFIED", "LOW", "HIGH")),
      f_optional = 0L
    )
  )
  expect_identical(Encoding(x$f_string), "UTF-8")
})

test_that("unset fields take defaults, except those with presence", {
  pool <- decode_pool()
  x <- proto_decode(msg_fixture("scalars_empty"), "zpb.decode.Scalars", pool)
  expect_false("f_optional" %in% names(x))
  expect_identical(x$f_int32, 0L)
  expect_identical(x$f_int64, 0)
  expect_identical(x$f_string, "")
  expect_identical(x$f_bytes, raw())
  expect_identical(x$f_bool, FALSE)
  expect_identical(as.character(x$f_enum), "LEVEL_UNSPECIFIED")

  none <- proto_decode(
    msg_fixture("scalars_empty"),
    "zpb.decode.Scalars",
    pool,
    defaults = FALSE
  )
  expect_length(none, 0L)
  set <- proto_decode(
    msg_fixture("scalars_set"),
    "zpb.decode.Scalars",
    pool,
    defaults = FALSE
  )
  expect_identical(set$f_optional, 0L)
})

test_that("64-bit values past 2^53 and -2^31 warn when decoded as numbers", {
  pool <- decode_pool()
  expect_warning(
    x <- proto_decode(msg_fixture("scalars_big"), "zpb.decode.Scalars", pool),
    class = "zuproto_precision_loss"
  )
  expect_identical(x$f_int32, NA_integer_)
  expect_identical(x$f_sint32, NA_integer_)
  expect_identical(x$f_int64, 2^63 - 1)
})

test_that("as character, only the -2^31 values warn", {
  pool <- decode_pool()
  w <- expect_warning(
    y <- proto_decode(
      msg_fixture("scalars_big"),
      "zpb.decode.Scalars",
      pool,
      int64 = "character"
    ),
    class = "zuproto_precision_loss"
  )
  expect_identical(w$n, 2)
  expect_identical(y$f_int64, "9223372036854775807")
  expect_identical(y$f_uint64, "18446744073709551615")
  expect_identical(y$f_sfixed64, "0")
})

test_that("values that are exact do not warn", {
  pool <- decode_pool()
  expect_no_warning(proto_decode(
    msg_fixture("scalars_set"),
    "zpb.decode.Scalars",
    pool
  ))
})

test_that("enums decode as factors, integers or names", {
  pool <- decode_pool()
  raw <- msg_fixture("scalars_set")
  expect_identical(
    proto_decode(raw, "zpb.decode.Scalars", pool, enums = "integer")$f_enum,
    2L
  )
  expect_identical(
    proto_decode(raw, "zpb.decode.Scalars", pool, enums = "character")$f_enum,
    "HIGH"
  )
})

test_that("an enum number the enum lacks is NA with a warning, or kept as an integer", {
  pool <- decode_pool()
  raw <- c(as.raw(0x80), as.raw(0x01), as.raw(5)) # field 16 (f_enum) = 5
  w <- expect_warning(
    x <- proto_decode(raw, "zpb.decode.Scalars", pool),
    class = "zuproto_unknown_enum"
  )
  expect_identical(w$n, 1)
  expect_identical(as.integer(x$f_enum), NA_integer_)
  expect_identical(levels(x$f_enum), c("LEVEL_UNSPECIFIED", "LOW", "HIGH"))
  expect_warning(
    y <- proto_decode(raw, "zpb.decode.Scalars", pool, enums = "character"),
    class = "zuproto_unknown_enum"
  )
  expect_identical(y$f_enum, NA_character_)
  expect_no_warning(
    z <- proto_decode(raw, "zpb.decode.Scalars", pool, enums = "integer")
  )
  expect_identical(z$f_enum, 5L)
})

test_that("bytes decode as raw or base64", {
  raw <- msg_fixture("scalars_set")
  x <- proto_decode(raw, "zpb.decode.Scalars", decode_pool(), bytes = "base64")
  expect_identical(x$f_bytes, "AAEC/w==")
})

test_that("repeated fields decode to vectors and lists", {
  x <- proto_decode(
    msg_fixture("repeated"),
    "zpb.decode.Repeated",
    decode_pool()
  )
  expect_identical(x$packed, 1:3)
  expect_identical(x$unpacked, 4:5)
  expect_identical(x$strings, c("a", "b"))
  expect_identical(x$blobs, list(as.raw(1), as.raw(2)))
  expect_identical(
    x$levels,
    factor(c("LOW", "HIGH"), levels = c("LEVEL_UNSPECIFIED", "LOW", "HIGH"))
  )
  expect_identical(
    x$points,
    list(
      list(x = 1L, y = 2L),
      list(x = 3L, y = 4L, `next` = list(x = 5L, y = 0L))
    )
  )
  expect_identical(x$doubles, double())
  expect_identical(x$flags, c(TRUE, FALSE))
})

test_that("maps decode to named vectors and lists, sorted by key", {
  x <- proto_decode(msg_fixture("maps"), "zpb.decode.Maps", decode_pool())
  expect_identical(x$by_string, c(a = 1L, b = 2L))
  expect_identical(x$by_int32, c(`-1` = "minus", `2` = "two", `10` = "ten"))
  expect_identical(x$by_int64, c(`1` = "one", `9007199254740993` = "big"))
  expect_identical(x$by_bool, c(false = "f", true = "t"))
  expect_identical(x$points, list(`7` = list(x = 7L, y = 0L)))
  expect_identical(as.character(x$levels), c("HIGH", "LOW"))
  expect_identical(names(x$levels), c("y", "z"))
})

test_that("a oneof gives only its set member", {
  pool <- decode_pool()
  expect_identical(
    proto_decode(msg_fixture("choice_text"), "zpb.decode.Choice", pool),
    list(text = "hi", other = "o")
  )
  expect_identical(
    proto_decode(msg_fixture("choice_point"), "zpb.decode.Choice", pool),
    list(point = list(x = 1L, y = 0L), other = "")
  )
  expect_identical(
    proto_decode(msg_fixture("choice_none"), "zpb.decode.Choice", pool),
    list(other = "o")
  )
})

test_that("well-known types decode as design section 6.3 maps them", {
  x <- proto_decode(
    msg_fixture("wellknown"),
    "zpb.decode.WellKnown",
    decode_pool()
  )
  utc <- function(s) as.POSIXct(s, origin = "1970-01-01", tz = "UTC")

  expect_s3_class(x$when, "POSIXct")
  expect_identical(attr(x$when, "tzone"), "UTC")
  # 2026-10-25T12:34:56.123456789Z: nanos rounded to the microsecond.
  expect_lt(abs(unclass(x$when) - (1792931696 + 0.123457)), 1e-6)
  expect_equal(
    unclass(x$when),
    unclass(as.POSIXct("2026-10-25 12:34:56", tz = "UTC")) + 0.123457,
    tolerance = 1e-9,
    ignore_attr = TRUE
  )
  expect_identical(x$took, as.difftime(90.5, units = "secs"))
  expect_identical(x$i32, -3L)
  expect_identical(x$i64, 12)
  expect_identical(x$u32, 4e9)
  expect_identical(x$u64, 5)
  expect_identical(x$f32, 1.5)
  expect_identical(x$f64, 2.5)
  expect_identical(x$flag, TRUE)
  expect_identical(x$text, "w")
  expect_identical(x$blob, as.raw(c(0, 1)))
  expect_identical(
    x$meta,
    list(a = 1, b = list(TRUE, NULL, "x"), c = list(d = "e"))
  )
  expect_identical(x$value, "str")
  expect_identical(x$list, list(1, "two", NULL))
  expect_identical(
    x$any,
    list(
      type_url = "type.googleapis.com/zpb.decode.Point",
      value = as.raw(c(0x08, 0x01, 0x10, 0x02))
    )
  )
  expect_identical(x$mask, c("a.b", "c"))
  expect_identical(x$empty, setNames(list(), character()))
  expect_identical(x$times, utc(c(0, 946684800.5)))
  expect_false("unset_wrapper" %in% names(x))
})

test_that("a well-known type decodes on its own as it does as a field", {
  pool <- proto_pool()
  bytes <- as.raw(c(0x08, 0x01, 0x10, 0x80, 0xca, 0xb5, 0xee, 0x01))
  ts <- proto_decode(bytes, "google.protobuf.Timestamp", pool)
  expect_identical(unclass(ts), structure(1.5, tzone = "UTC"))
  expect_identical(
    proto_decode(as.raw(c(0x08, 0x2a)), "google.protobuf.Int32Value", pool),
    42L
  )
})

test_that("nested messages decode recursively", {
  x <- proto_decode(msg_fixture("nested_3"), "zpb.decode.Nested", decode_pool())
  expect_identical(
    x,
    list(depth = 1L, child = list(depth = 2L, child = list(depth = 3L)))
  )
})

test_that("proto2: unset optional fields are left out, required ones are not checked", {
  pool <- decode_pool()
  expect_identical(
    proto_decode(msg_fixture("legacy_min"), "zpb.decode2.Legacy", pool),
    list(id = 1L, values = integer())
  )
  expect_identical(
    proto_decode(raw(), "zpb.decode2.Legacy", pool),
    list(values = integer())
  )
})

test_that("set extensions decode under bracketed full names", {
  x <- proto_decode(
    msg_fixture("legacy_ext"),
    "zpb.decode2.Legacy",
    decode_pool()
  )
  expect_identical(
    x[c("id", "name", "values")],
    list(id = 2L, name = "x", values = 3L)
  )
  expect_identical(x[["[zpb.decode2.tag]"]], "t")
  expect_identical(x[["[zpb.decode2.codes]"]], 1:2)
})

test_that("unknown fields are dropped or kept as raw bytes", {
  pool <- decode_pool()
  raw <- msg_fixture("unknown_field")
  dropped <- proto_decode(raw, "zpb.decode.Point", pool)
  expect_identical(dropped, list(x = 1L, y = 0L))
  kept <- proto_decode(raw, "zpb.decode.Point", pool, unknown = "keep")
  expect_identical(attr(kept, "proto_unknown"), as.raw(c(0x98, 0x06, 0x05)))
  expect_null(attr(
    proto_decode(
      msg_fixture("nested_3"),
      "zpb.decode.Nested",
      pool,
      unknown = "keep"
    ),
    "proto_unknown"
  ))
})

test_that("input can be a path or a connection", {
  skip_if_not_installed("withr")
  path <- withr::local_tempfile(fileext = ".binpb")
  writeBin(msg_fixture("nested_3"), path)
  pool <- decode_pool()
  expected <- proto_decode(msg_fixture("nested_3"), "zpb.decode.Nested", pool)
  expect_identical(proto_decode(path, "zpb.decode.Nested", pool), expected)
  con <- file(path, "rb")
  withr::defer(close(con))
  expect_identical(proto_decode(con, "zpb.decode.Nested", pool), expected)
})

test_that("input beyond max_size is refused before decoding", {
  skip_if_not_installed("withr")
  pool <- decode_pool()
  raw <- msg_fixture("scalars_set")
  err <- expect_error(
    proto_decode(raw, "zpb.decode.Scalars", pool, max_size = 10),
    class = "zuproto_size_limit"
  )
  expect_s3_class(err, "zuproto_limit_error")
  expect_identical(err$limit, "max_size")

  path <- withr::local_tempfile(fileext = ".binpb")
  writeBin(raw, path)
  expect_error(
    proto_decode(path, "zpb.decode.Scalars", pool, max_size = 10),
    class = "zuproto_size_limit"
  )
  con <- rawConnection(raw)
  withr::defer(close(con))
  expect_error(
    proto_decode(con, "zpb.decode.Scalars", pool, max_size = 10),
    class = "zuproto_size_limit"
  )
})

test_that("malformed bytes are a parse error", {
  pool <- decode_pool()
  expect_error(
    proto_decode(as.raw(c(0x0a, 0xff)), "zpb.decode.Repeated", pool),
    class = "zuproto_parse_error"
  )
  expect_error(
    proto_decode(as.raw(0xff), "zpb.decode.Point", pool),
    class = "zuproto_parse_error"
  )
})

test_that("a length prefix of 2^31 with three bytes after it is a parse error", {
  raw <- c(as.raw(0x1a), varint(2^31), as.raw(c(0x61, 0x62, 0x63))) # field 3, strings
  expect_error(
    proto_decode(raw, "zpb.decode.Repeated", decode_pool()),
    class = "zuproto_parse_error"
  )
})

test_that("a packed field claiming 10^9 elements is a parse error", {
  raw <- c(as.raw(0x0a), varint(1e9), as.raw(c(1, 2, 3))) # field 1, packed
  expect_error(
    proto_decode(raw, "zpb.decode.Repeated", decode_pool()),
    class = "zuproto_parse_error"
  )
})

test_that("nesting beyond max_depth is a depth limit error", {
  # nested(n) is n messages, one inside the next: depth n - 1.
  nested <- function(depth) {
    raw <- as.raw(c(0x08, 0x01)) # depth = 1
    for (i in seq_len(depth - 1)) {
      raw <- c(as.raw(c(0x08, 0x01, 0x12)), varint(length(raw)), raw)
    }
    raw
  }
  pool <- decode_pool()
  expect_no_error(proto_decode(nested(101), "zpb.decode.Nested", pool))
  err <- expect_error(
    proto_decode(nested(102), "zpb.decode.Nested", pool),
    class = "zuproto_depth_limit"
  )
  expect_s3_class(err, "zuproto_limit_error")
  expect_identical(err$limit, "max_depth")
  expect_no_error(proto_decode(
    nested(6),
    "zpb.decode.Nested",
    pool,
    max_depth = 5
  ))
  expect_error(
    proto_decode(nested(7), "zpb.decode.Nested", pool, max_depth = 5),
    class = "zuproto_depth_limit"
  )
})

test_that("inputs that expand a lot decode within the schema's ceiling", {
  # The ceiling is the most a message of the type can need (design section
  # 12): packed zeros expand 4x (int32) and 8x (double), empty sub-messages
  # to a whole struct each. None of these legitimate inputs may hit it.
  pool <- decode_pool()
  n <- 1e6
  zeros <- c(as.raw(0x0a), varint(n), raw(n)) # Repeated.packed, 10^6 zeros
  expect_length(
    proto_decode(
      zeros,
      "zpb.decode.Repeated",
      pool,
      max_size = length(zeros)
    )$packed,
    n
  )
  doubles <- c(as.raw(0x3a), varint(8 * 1e5), raw(8 * 1e5)) # Repeated.doubles
  expect_length(proto_decode(doubles, "zpb.decode.Repeated", pool)$doubles, 1e5)
  points <- rep(as.raw(c(0x32, 0x00)), 1e5) # Repeated.points: 10^5 empty Points
  expect_length(proto_decode(points, "zpb.decode.Repeated", pool)$points, 1e5)
})

test_that("invalid UTF-8 is an error in proto3 and proto2 strings alike", {
  pool <- decode_pool()
  bad <- as.raw(c(0xff, 0xfe))
  p3 <- c(as.raw(0x72), varint(2), bad) # Scalars.f_string, field 14
  p2 <- c(as.raw(0x12), varint(2), bad) # Legacy.name, field 2
  err <- expect_error(
    proto_decode(p3, "zpb.decode.Scalars", pool),
    class = "zuproto_invalid_utf8"
  )
  expect_s3_class(err, "zuproto_parse_error")
  expect_error(
    proto_decode(p2, "zpb.decode2.Legacy", pool),
    class = "zuproto_invalid_utf8"
  )
})

test_that("a string with a NUL byte is unrepresentable, naming the field", {
  raw <- c(as.raw(0x72), varint(3), as.raw(c(0x61, 0x00, 0x62)))
  err <- expect_error(
    proto_decode(raw, "zpb.decode.Scalars", decode_pool()),
    class = "zuproto_unrepresentable"
  )
  expect_identical(err$field, "zpb.decode.Scalars.f_string")
})

test_that("an unknown type is a zuproto_unknown_type error", {
  err <- expect_error(
    proto_decode(raw(), "no.Such", proto_pool()),
    class = "zuproto_unknown_type"
  )
  expect_identical(err$type, "no.Such")
})

test_that("unusable arguments are invalid arguments, naming the argument", {
  pool <- decode_pool()
  raw <- msg_fixture("nested_3")
  type <- "zpb.decode.Nested"
  cases <- list(
    int64 = list(int64 = "zuint"),
    enums = list(enums = "level"),
    defaults = list(defaults = NA),
    unknown = list(unknown = "save"),
    bytes = list(bytes = "hex"),
    max_size = list(max_size = 0),
    max_depth = list(max_depth = 1.5)
  )
  for (arg in names(cases)) {
    err <- expect_error(
      do.call(proto_decode, c(list(raw, type, pool), cases[[arg]])),
      class = "zuproto_invalid_argument"
    )
    expect_identical(err$arg, arg)
  }
  expect_error(
    proto_decode(list(), type, pool),
    class = "zuproto_invalid_argument"
  )
})

test_that("precision loss is warned exactly when a 64-bit value is not exact", {
  pool <- decode_pool()
  # Scalars.f_int64 (field 8) = 2^53 + 1 and = 2^60, as Python's protobuf
  # serialises them; R doubles cannot write 2^53 + 1 themselves.
  hex <- function(h) {
    as.raw(strtoi(substring(h, seq(1, nchar(h), 2), seq(2, nchar(h), 2)), 16L))
  }
  w <- expect_warning(
    x <- proto_decode(hex("408180808080808010"), "zpb.decode.Scalars", pool),
    class = "zuproto_precision_loss"
  )
  expect_identical(w$n, 1)
  expect_identical(x$f_int64, 2^53)
  expect_no_warning(
    y <- proto_decode(hex("40808080808080808010"), "zpb.decode.Scalars", pool)
  )
  expect_identical(y$f_int64, 2^60)
})

test_that("a negative Duration keeps its sign", {
  # Duration{seconds = -1, nanos = -500000000}, as Python's protobuf
  # serialises it.
  hex <- "08ffffffffffffffffff011080b6ca91feffffffff01"
  raw <- as.raw(strtoi(substring(hex, seq(1, 43, 2), seq(2, 44, 2)), 16L))
  x <- proto_decode(raw, "google.protobuf.Duration", proto_pool())
  expect_identical(x, as.difftime(-1.5, units = "secs"))
})

test_that("unknown fields are kept on nested and repeated messages", {
  # Repeated.points[0] = Point{x = 1, field 99 = 5}.
  inner <- as.raw(c(0x08, 0x01, 0x98, 0x06, 0x05))
  raw <- c(as.raw(0x32), varint(length(inner)), inner)
  x <- proto_decode(raw, "zpb.decode.Repeated", decode_pool(), unknown = "keep")
  expect_identical(
    attr(x$points[[1]], "proto_unknown"),
    as.raw(c(0x98, 0x06, 0x05))
  )
})

# A map whose values allocate, large enough for the gctorture CI job to
# collect a key's name while its value is built.
test_that("a map whose values allocate keeps every key", {
  pool <- decode_pool()
  # Maps.points (field 5): 200 entries uint32 -> Point{x}, values allocate.
  entry <- function(k) {
    point <- c(as.raw(0x08), varint(k))
    body <- c(
      as.raw(0x08),
      varint(k),
      as.raw(0x12),
      varint(length(point)),
      point
    )
    c(as.raw(0x2a), varint(length(body)), body)
  }
  raw <- do.call(c, lapply(1:200, entry))
  expected <- stats::setNames(lapply(1:200, function(k) list(x = k)), 1:200)
  x <- proto_decode(raw, "zpb.decode.Maps", pool, defaults = FALSE)
  expect_identical(x$points, expected)
})

test_that("max_depth is capped well below what the C stack can take", {
  pool <- decode_pool()
  err <- expect_error(
    proto_decode(raw(), "zpb.decode.Nested", pool, max_depth = 1001),
    class = "zuproto_invalid_argument"
  )
  expect_identical(err$arg, "max_depth")
  expect_no_error(proto_decode(
    raw(),
    "zpb.decode.Nested",
    pool,
    max_depth = 1000
  ))
})

test_that("a Struct key with a NUL byte is unrepresentable", {
  # Struct{fields: {"a\0b": Value{null_value}}}.
  entry <- as.raw(c(0x0a, 0x03, 0x61, 0x00, 0x62, 0x12, 0x02, 0x08, 0x00))
  raw <- c(as.raw(0x0a), as.raw(length(entry)), entry)
  expect_error(
    proto_decode(raw, "google.protobuf.Struct", proto_pool()),
    class = "zuproto_unrepresentable"
  )
})

test_that("arguments given at their defaults decode as when left out", {
  # proto_decode() skips checking arguments it was not given; both paths
  # must agree.
  pool <- decode_pool()
  for (name in c("scalars_set", "wellknown", "maps")) {
    raw <- msg_fixture(name)
    type <- fixture_types()[[name]]
    expect_identical(
      proto_decode(raw, type, pool),
      proto_decode(
        raw,
        type,
        pool,
        int64 = "double",
        enums = "factor",
        defaults = TRUE,
        unknown = "drop",
        bytes = "raw",
        max_size = 64 * 1024^2,
        max_depth = 100L
      )
    )
    x <- proto_decode(raw, type, pool, int64 = "character")
    expect_identical(
      proto_encode(x, type, pool),
      proto_encode(
        x,
        type,
        pool,
        deterministic = TRUE,
        unknown = TRUE,
        check_required = TRUE,
        extra = "error"
      )
    )
    expect_identical(
      proto_to_json(raw, type, pool),
      proto_to_json(
        raw,
        type,
        pool,
        emit_defaults = FALSE,
        proto_names = FALSE,
        enums = "name",
        max_size = 64 * 1024^2,
        max_depth = 100L
      )
    )
  }
})

test_that("a wire NaN with R's NA payload decodes as NaN, not NA, and re-encodes", {
  # Found by fuzz_build: the double 0x7FF00000000007A2 is R's NA_real_.
  pool <- decode_pool()
  na_bits <- as.raw(c(0xa2, 0x07, 0, 0, 0, 0, 0xf0, 0x7f))
  raw <- c(as.raw(0x3a), as.raw(8), na_bits) # Repeated.doubles, packed
  x <- proto_decode(raw, "zpb.decode.Repeated", pool, defaults = FALSE)
  expect_true(is.nan(x$doubles))
  y <- proto_decode(
    proto_encode(x, "zpb.decode.Repeated", pool),
    "zpb.decode.Repeated",
    pool,
    defaults = FALSE
  )
  expect_true(is.nan(y$doubles))
  single <- proto_decode(
    c(as.raw(0x09), na_bits),
    "zpb.decode.Scalars",
    pool,
    defaults = FALSE
  )
  expect_true(is.nan(single$f_double))
})

test_that("Timestamp and Duration seconds beyond 2^53 warn of precision loss", {
  # Found by fuzz_build: such seconds cannot be held by a double.
  pool <- proto_pool()
  far <- c(as.raw(0x08), as.raw(c(rep(0xff, 8), 0x7f))) # seconds = 2^63 - 1
  expect_warning(
    proto_decode(far, "google.protobuf.Timestamp", pool),
    class = "zuproto_precision_loss"
  )
  expect_warning(
    proto_decode(far, "google.protobuf.Duration", pool),
    class = "zuproto_precision_loss"
  )
  near <- c(as.raw(0x08), varint(2^53)) # exactly 2^53: no loss
  expect_no_warning(proto_decode(near, "google.protobuf.Timestamp", pool))
})
