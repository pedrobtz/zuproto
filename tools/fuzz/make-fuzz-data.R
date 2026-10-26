#!/usr/bin/env Rscript
# Writes the fuzz targets' data, from files the package already has. Run from
# the package root after the fixtures or wkt.binpb change:
#
#   Rscript tools/fuzz/make-fuzz-data.R
#
# * tools/fuzz/data.h: the well-known types and the decode fixture schemas
#   as one descriptor set, as a C array. A FileDescriptorSet is its files
#   back to back, so the concatenation is a set, in dependency order.
# * tools/fuzz/seeds/{decode,build}/: each message fixture, prefixed with
#   the byte that selects its type (zpb_fuzz_types in fuzz.h).
# * tools/fuzz/seeds/json/: the same messages as protobuf JSON.
suppressPackageStartupMessages(library(zuproto))
read_bin <- function(path) readBin(path, "raw", file.size(path))
fixtures <- "tests/testthat/fixtures"

set <- c(
  read_bin("inst/descriptors/wkt.binpb"),
  read_bin(file.path(fixtures, "decode.binpb")),
  read_bin(file.path(fixtures, "decode2.binpb"))
)
bytes <- paste0("0x", as.character(set))
rows <- split(bytes, ceiling(seq_along(bytes) / 12))
writeLines(c(
  "/* Written by tools/fuzz/make-fuzz-data.R; do not edit. */",
  "#include <stddef.h>",
  "const unsigned char zpb_fuzz_descriptors[] = {",
  paste0("    ", vapply(rows, paste, character(1), collapse = ", "), ","),
  "};",
  sprintf("const size_t zpb_fuzz_descriptors_len = %d;", length(set))
), "tools/fuzz/data.h")

types <- c(
  "zpb.decode.Scalars", "zpb.decode.Repeated", "zpb.decode.Maps",
  "zpb.decode.Choice", "zpb.decode.WellKnown", "zpb.decode.Nested",
  "zpb.decode2.Legacy", "google.protobuf.Struct", "google.protobuf.Value",
  "google.protobuf.Any", "google.protobuf.Timestamp",
  "google.protobuf.FileDescriptorSet", "google.protobuf.Duration",
  "zpb.decode.Point", "zpb.decode.Uint64Keys", "zpb.decode.Outer"
)
pool <- proto_pool(set)
manifest <- utils::read.delim(file.path(fixtures, "msg", "MANIFEST.tsv"))
for (dir in c("decode", "build", "json")) {
  unlink(file.path("tools/fuzz/seeds", dir), recursive = TRUE)
  dir.create(file.path("tools/fuzz/seeds", dir), recursive = TRUE)
}
hex_raw <- function(h) {
  if (!nzchar(h)) return(raw())
  as.raw(strtoi(substring(h, seq(1, nchar(h), 2), seq(2, nchar(h), 2)), 16L))
}
for (i in seq_len(nrow(manifest))) {
  sel <- match(manifest$type[[i]], types) - 1L
  msg <- hex_raw(readLines(file.path(fixtures, "msg", paste0(manifest$name[[i]], ".hex"))))
  seed <- c(as.raw(sel), msg)
  for (dir in c("decode", "build")) {
    writeBin(seed, file.path("tools/fuzz/seeds", dir, manifest$name[[i]]))
  }
  json <- tryCatch(proto_to_json(msg, manifest$type[[i]], pool), error = function(e) NULL)
  if (!is.null(json)) {
    writeBin(c(as.raw(sel), charToRaw(json)), file.path("tools/fuzz/seeds/json", manifest$name[[i]]))
  }
}
# A descriptor set is a hostile-input target of its own.
writeBin(c(as.raw(match("google.protobuf.FileDescriptorSet", types) - 1L), set),
         file.path("tools/fuzz/seeds/decode", "descriptor_set"))
cat(sprintf("==> data.h: %d bytes; %d seeds\n", length(set),
            length(list.files("tools/fuzz/seeds", recursive = TRUE))))
