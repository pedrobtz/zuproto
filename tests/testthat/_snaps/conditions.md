# argument and pool errors read well

    Code
      proto_decode(raw(), "google.protobuf.Empty", "pool")
    Condition
      Error in `proto_decode()`:
      ! `pool` must be a pool from proto_pool().
    Code
      proto_pool("no/such/file.binpb")
    Condition
      Error in `proto_pool()`:
      ! Cannot read file 'no/such/file.binpb': it does not exist.
    Code
      proto_pool_add(proto_pool(), fixture("uses_dep"))
    Condition
      Error in `proto_pool_add()`:
      ! Cannot add 'uses_dep.proto': it imports 'dep.proto', which is neither in the set nor in the pool. Build the set with `protoc --include_imports`, or add that file first.
    Code
      proto_pool_add(proto_pool(fixture("dep")), fixture("dep_v2"))
    Condition
      Error in `proto_pool_add()`:
      ! Cannot add 'dep.proto': a different file of that name is already in the pool.
    Code
      proto_decode(raw(), "no.such.Type", proto_pool())
    Condition
      Error in `proto_decode()`:
      ! Message type 'no.such.Type' is not in the pool.

# decoding errors read well

    Code
      proto_decode(as.raw(10), "zpb.decode.Scalars", pool)
    Condition
      Error in `proto_decode()`:
      ! Cannot decode the input as 'zpb.decode.Scalars': the bytes are not a valid message of that type.
    Code
      proto_decode(c(as.raw(114), varint(2), bad), "zpb.decode.Scalars", pool)
    Condition
      Error in `proto_decode()`:
      ! Cannot decode the input as 'zpb.decode.Scalars': a string field is not valid UTF-8.
    Code
      proto_decode(as.raw(c(114, 1, 0)), "zpb.decode.Scalars", pool)
    Condition
      Error in `proto_decode()`:
      ! Cannot decode the input as 'zpb.decode.Scalars': field 'zpb.decode.Scalars.f_string' holds a string R cannot, one containing a NUL byte.
    Code
      proto_decode(c(as.raw(c(8, 1, 18, 6)), nested), "zpb.decode.Nested", pool,
      max_depth = 1)
    Condition
      Error in `proto_decode()`:
      ! Cannot decode the input as 'zpb.decode.Nested': messages are nested deeper than `max_depth` (1).
    Code
      proto_decode(msg_fixture("scalars_set"), "zpb.decode.Scalars", pool, max_size = 10)
    Condition
      Error in `proto_decode()`:
      ! The input is larger than `max_size` (10 bytes).
    Code
      proto_decode_df(rep(list(nested), 3), "zpb.decode.Nested", pool, max_rows = 2)
    Condition
      Error in `proto_decode_df()`:
      ! There are more than `max_rows` (2) rows.

# encoding errors read well

    Code
      proto_encode(list(f_int32 = 1.5), "zpb.decode.Scalars", pool)
    Condition
      Error in `proto_encode()`:
      ! Cannot encode as 'zpb.decode.Scalars': Field `f_int32` must be a whole number in the 32-bit signed range.
    Code
      proto_encode(list(points = list(list(x = "a"))), "zpb.decode.Repeated", pool)
    Condition
      Error in `proto_encode()`:
      ! Cannot encode as 'zpb.decode.Repeated': Field `points[1].x` must be numeric.
    Code
      proto_encode(list(nope = 1), "zpb.decode.Scalars", pool)
    Condition
      Error in `proto_encode()`:
      ! Cannot encode as 'zpb.decode.Scalars': Field `nope` is not a field of the message type. Use `extra = "ignore"` to skip names the type does not define.
    Code
      proto_encode(list(name = "x"), "zpb.decode2.Legacy", pool)
    Condition
      Error in `proto_encode()`:
      ! Cannot encode as 'zpb.decode2.Legacy': a required field is not set.
    Code
      proto_encode(deep, "zpb.decode.Nested", pool)
    Condition
      Error in `proto_encode()`:
      ! Cannot encode as 'zpb.decode.Nested': messages are nested deeper than 1000 levels, the most zuproto encodes.
    Code
      zuproto:::encode_error(list(error = "other"), "pkg.M", NULL)
    Condition
      Error:
      ! Cannot encode as 'pkg.M': internal error 'other'.
    Code
      zuproto:::decode_error(list(error = "out_of_memory"), "pkg.M", 1, 1, NULL)
    Condition
      Error:
      ! Cannot decode the input as 'pkg.M': out of memory.

# JSON errors read well

    Code
      proto_from_json("{\"f_int32\": \"x\"}", "zpb.decode.Scalars", pool)
    Condition
      Error in `proto_from_json()`:
      ! Cannot convert 'zpb.decode.Scalars' to or from JSON: Error parsing JSON @1:15: Non-number characters in quoted integer.

# warnings read well

    Code
      x <- proto_decode(msg_fixture("scalars_big"), "zpb.decode.Scalars", pool)
    Condition
      Warning in `proto_decode()`:
      4 values in 'zpb.decode.Scalars' could not be represented exactly: 64-bit integers beyond 2^53 were rounded, and 32-bit -2^31 became NA. Use `int64 = "character"` for exact 64-bit values.
    Code
      x <- proto_decode(raw, "zpb.decode.Scalars", pool)
    Condition
      Warning in `proto_decode()`:
      1 enum value in 'zpb.decode.Scalars' named no value of its enum and became NA.

