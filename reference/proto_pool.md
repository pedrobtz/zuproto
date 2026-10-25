# Descriptor pools

A pool holds the message types zuproto can decode and encode. It is
built from serialised `FileDescriptorSet`s, which `protoc` and `buf`
write:

## Usage

``` r
proto_pool(x = NULL)

proto_pool_add(pool, x)
```

## Arguments

- x:

  A serialised `FileDescriptorSet`: a raw vector, a path to a file, or a
  connection. `NULL` for the well-known types only.

- pool:

  A pool from `proto_pool()`.

## Value

`proto_pool()` returns a pool. `proto_pool_add()` returns `pool`,
invisibly, after adding `x` to it.

## Details

    protoc --include_imports --descriptor_set_out=schema.binpb schema.proto
    buf build -o schema.binpb

Every pool starts with the well-known types (`google/protobuf/*.proto`,
including `descriptor.proto`), so a set need not include them.

Descriptor sets are trusted input: upb checks them, but less thoroughly
than `protoc` does. Load sets you or your tools produced, not ones from
an untrusted source. Message bytes, by contrast, are never trusted.

Files are added in dependency order, whatever order the set lists them
in. A file already in the pool is skipped if its contents are identical
and is a `zuproto_pool_conflict` if they are not; the same holds for a
file listed twice. A file importing one that is neither in the set nor
in the pool is a `zuproto_pool_error` naming both, and nothing from the
set is added. Extensions are loaded with the files that declare them.

## See also

[`proto_types()`](https://pedrobtz.github.io/zuproto/reference/proto_types.md)
and
[`proto_fields()`](https://pedrobtz.github.io/zuproto/reference/proto_types.md)
to see what a pool holds.

## Examples

``` r
pool <- proto_pool()
pool
#> <proto_pool: 11 files, 61 message types>
"google.protobuf.Timestamp" %in% proto_types(pool)$name
#> [1] TRUE
```
