# The conformance testee (design section 15): protobuf's
# conformance_test_runner starts this program and sends it requests on
# stdin, each a 4-byte little-endian length and a ConformanceRequest; it
# answers each on stdout the same way with a ConformanceResponse. Run it
# through tools/conformance/run, not directly.
#
# Every payload goes through zuproto's R path: binary is decoded to R
# values with proto_decode() and encoded back with proto_encode(), so the
# suite tests the mapping R users get, not only upb. int64 = "character",
# enums = "integer" and unknown = "keep" make that round trip lossless.
suppressPackageStartupMessages(library(zuproto))

script_dir <- dirname(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)))
pool <- proto_pool(file.path(script_dir, "conformance.binpb"))

input <- file("stdin", "rb")
output <- file("/dev/stdout", "wb")

le32 <- function(n) as.raw(bitwAnd(bitwShiftR(n, c(0L, 8L, 16L, 24L)), 255L))

response <- function(...) proto_encode(list(...), "conformance.ConformanceResponse", pool)

message_text <- function(e) gsub("\\s+", " ", conditionMessage(e))

handle <- function(bytes) {
  req <- proto_decode(bytes, "conformance.ConformanceRequest", pool, enums = "character",
                      int64 = "character", defaults = FALSE)
  type <- req$message_type
  if (identical(type, "conformance.FailureSet")) {
    # The expected failures come from --failure_list instead.
    return(response(protobuf_payload = raw()))
  }
  fmt <- req$requested_output_format
  if (!fmt %in% c("PROTOBUF", "JSON")) {
    return(response(skipped = sprintf("output format %s is not supported", fmt)))
  }
  if (!is.null(req$jspb_payload) || !is.null(req$text_payload)) {
    return(response(skipped = "JSPB and text format input are not supported"))
  }

  decode <- function(raw) {
    proto_decode(raw, type, pool, int64 = "character", enums = "integer", defaults = FALSE,
                 unknown = "keep")
  }
  value <- tryCatch(
    if (!is.null(req$protobuf_payload)) {
      decode(req$protobuf_payload)
    } else {
      ignore <- identical(req$test_category, "JSON_IGNORE_UNKNOWN_PARSING_TEST")
      decode(proto_from_json(req$json_payload, type, pool, ignore_unknown = ignore,
                             check_required = FALSE))
    },
    zuproto_error = function(e) e
  )
  if (inherits(value, "error")) {
    return(response(parse_error = message_text(value)))
  }

  out <- tryCatch(
    {
      bin <- proto_encode(value, type, pool, check_required = FALSE)
      if (fmt == "PROTOBUF") list(protobuf_payload = bin) else list(json_payload = proto_to_json(bin, type, pool))
    },
    zuproto_error = function(e) list(serialize_error = message_text(e))
  )
  do.call(response, out)
}

repeat {
  header <- readBin(input, "raw", 4L)
  if (length(header) < 4L) break
  n <- sum(as.integer(header) * c(1, 256, 65536, 16777216))
  bytes <- readBin(input, "raw", n)
  out <- tryCatch(handle(bytes), error = function(e) response(runtime_error = message_text(e)))
  writeBin(c(le32(length(out)), out), output)
  flush(output)
}
