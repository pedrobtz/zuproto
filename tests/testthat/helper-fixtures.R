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
