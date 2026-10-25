# The descriptor sets tools/make-test-descriptors compiles from
# fixtures/proto/.

# The raw bytes of fixtures/<name>.binpb.
fixture <- function(name) {
  path <- test_path("fixtures", paste0(name, ".binpb"))
  readBin(path, "raw", file.size(path))
}

# A pool with the well-known types plus the named fixture sets.
fixture_pool <- function(...) {
  pool <- proto_pool()
  for (name in c(...)) {
    proto_pool_add(pool, fixture(name))
  }
  pool
}

# The bytes of message fixture fixtures/msg/<name>.hex
# (tools/make-fixtures.py), stored as hex text.
msg_fixture <- function(name) {
  hex <- readLines(test_path("fixtures", "msg", paste0(name, ".hex")))
  if (!nzchar(hex)) {
    return(raw())
  }
  as.raw(strtoi(
    substring(hex, seq(1, nchar(hex), 2), seq(2, nchar(hex), 2)),
    16L
  ))
}

# A pool holding the decode fixture schemas.
decode_pool <- function() fixture_pool("decode", "decode2")

# A varint, as raw bytes.
varint <- function(n) {
  out <- raw()
  repeat {
    byte <- n %% 128
    n <- n %/% 128
    if (n == 0) {
      return(c(out, as.raw(byte)))
    }
    out <- c(out, as.raw(byte + 128))
  }
}

# The message type of each message fixture, by name, from MANIFEST.tsv.
fixture_types <- function() {
  manifest <- utils::read.delim(test_path("fixtures", "msg", "MANIFEST.tsv"))
  stats::setNames(manifest$type, manifest$name)
}
