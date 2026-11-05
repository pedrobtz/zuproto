# a directory is named as one, not as missing

    Code
      proto_pool(dir)
    Condition
      Error in `proto_pool()`:
      ! Cannot read file '<dir>': it is a directory.
    Code
      proto_decode(dir, "zpb.decode.Nested", pool)
    Condition
      Error in `proto_decode()`:
      ! Cannot read file '<dir>': it is a directory.
    Code
      proto_read_delimited(dir, "zpb.decode.Nested", pool, each = print)
    Condition
      Error in `proto_read_delimited()`:
      ! Cannot read file '<dir>': it is a directory.

