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
    Code
      proto_pool(file("no/such/file.binpb"))
    Condition
      Error in `proto_pool()`:
      ! Cannot open connection: cannot open file 'no/such/file.binpb': No such file or directory.

# a string the native encoding cannot read is described

    Code
      proto_encode(list(f_string = x), "zpb.decode.Scalars", pool)
    Condition
      Error in `proto_encode()`:
      ! Cannot encode as 'zpb.decode.Scalars': Field `f_string` must be text the native encoding can read.
    Code
      proto_from_json(x, "zpb.decode.Scalars", pool)
    Condition
      Error in `proto_from_json()`:
      ! Cannot convert 'zpb.decode.Scalars' to or from JSON: the native encoding cannot read the JSON text.

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
    Code
      x <- proto_enums(low, "low.E")
    Condition
      Warning in `proto_enums()`:
      1 enum number in 'low.E' could not be represented: -2^31 became NA.

# JSON errors read well

    Code
      proto_from_json("{\"f_int32\": \"x\"}", "zpb.decode.Scalars", pool)
    Condition
      Error in `proto_from_json()`:
      ! Cannot convert 'zpb.decode.Scalars' to or from JSON: Error parsing JSON @1:15: Non-number characters in quoted integer.
    Code
      proto_pack_any(list(), "zpb.decode.Point", pool, prefix = "x.io")
    Condition
      Error in `proto_pack_any()`:
      ! `prefix` must be a single string ending in /.
    Code
      proto_pack_any(list(), "zpb.decode.Point", pool, foo = 1)
    Condition
      Error in `proto_pack_any()`:
      ! `...` takes only proto_encode's options (`deterministic`, `unknown`, `check_required`, `extra`); not `foo`.
    Code
      proto_unpack_any(list(type_url = "x", value = raw()), pool)
    Condition
      Error in `proto_unpack_any()`:
      ! `x$type_url` ('x') must name a type after its last /.
    Code
      proto_from_json(bad, "zpb.decode.Scalars", pool)
    Condition
      Error in `proto_from_json()`:
      ! Cannot convert 'zpb.decode.Scalars' to or from JSON: the JSON text is not valid UTF-8.
    Code
      proto_from_json(bytes, "zpb.decode.Scalars", pool)
    Condition
      Error in `proto_from_json()`:
      ! `json` must be text, not a string marked as bytes.

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
      proto_encode(list(f_enum = factor(bad)), "zpb.decode.Scalars", pool)
    Condition
      Error in `proto_encode()`:
      ! Cannot encode as 'zpb.decode.Scalars': Field `f_enum` must be valid UTF-8.
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
    Code
      zuproto:::decode_error(list(error = "arena_limit"), "pkg.M", 1e+06, 100, NULL)
    Condition
      Error:
      ! Cannot decode the input as 'pkg.M': it needs more memory than a message of that type and size can legitimately need.
    Code
      zuproto:::decode_error(list(error = "frame_too_long", field = "pkg.M.items"),
      "pkg.M", 1e+06, 100, NULL)
    Condition
      Error:
      ! Cannot decode the input as 'pkg.M': field 'pkg.M.items' has 2^31 elements or more, too many for the rows of a data frame.
    Code
      proto_encode(as.Date("2026-01-01"), "google.protobuf.Value", pool)
    Condition
      Error in `proto_encode()`:
      ! Cannot encode as 'google.protobuf.Value': The value is a classed vector a Value cannot hold; convert it to a number or a string first.
    Code
      proto_encode(c(a = 1), "google.protobuf.Value", pool)
    Condition
      Error in `proto_encode()`:
      ! Cannot encode as 'google.protobuf.Value': The value is a named vector; give a Struct as a named list.
    Code
      proto_encode(list(f_int32 = sum), "zpb.decode.Scalars", pool)
    Condition
      Error in `proto_encode()`:
      ! Cannot encode as 'zpb.decode.Scalars': Field `f_int32` must be a vector or a list.
    Code
      proto_encode(list(f_uint64 = " -1"), "zpb.decode.Scalars", pool)
    Condition
      Error in `proto_encode()`:
      ! Cannot encode as 'zpb.decode.Scalars': Field `f_uint64` must be a decimal integer from 0 to 2^64 - 1.
    Code
      proto_write_delimited(list(), "zpb.decode.Point", pool, determinstic = TRUE)
    Condition
      Error in `proto_write_delimited()`:
      ! `...` takes only proto_encode's options (`deterministic`, `unknown`, `check_required`, `extra`); not `determinstic`.
    Code
      proto_write_delimited(list(list(x = 1L)), "zpb.decode.Point", pool, path = "no/such/dir/x.bin")
    Condition
      Error in `proto_write_delimited()`:
      ! Cannot write 'no/such/dir/x.bin': cannot open file 'no/such/dir/x.bin': No such file or directory.

