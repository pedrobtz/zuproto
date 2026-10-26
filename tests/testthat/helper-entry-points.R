# Each entry point called with a type and a pool and otherwise minimal
# arguments, for test-entry-points.R.
entry_points <- function() {
  list(
    proto_decode = function(type, pool) proto_decode(raw(), type, pool),
    proto_encode = function(type, pool) proto_encode(list(), type, pool),
    proto_decode_df = function(type, pool) {
      proto_decode_df(list(raw()), type, pool)
    },
    proto_read_delimited = function(type, pool) {
      proto_read_delimited(as.raw(0), type, pool)
    },
    proto_write_delimited = function(type, pool) {
      proto_write_delimited(list(list()), type, pool)
    },
    proto_to_json = function(type, pool) proto_to_json(raw(), type, pool),
    proto_from_json = function(type, pool) proto_from_json("{}", type, pool)
  )
}
