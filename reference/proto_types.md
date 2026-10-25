# Message types and their fields

`proto_types()` lists every message type in a pool, nested types
included, as a data frame. `proto_fields()` lists the fields of one
type, followed by the extensions the pool knows for it.

## Usage

``` r
proto_types(pool)

proto_fields(pool, type)
```

## Arguments

- pool:

  A pool from
  [`proto_pool()`](https://pedrobtz.github.io/zuproto/reference/proto_pool.md).

- type:

  A message type's full name, such as `"google.protobuf.Timestamp"`.

## Value

`proto_types()`: a data frame with columns `name` (full name), `file`
(the `.proto` file declaring it) and `fields` (the number of fields),
sorted by name. Map entry types are left out.

`proto_fields()`: a data frame with one row per field and columns

- `name`: the field's name, or `[full.name]` for an extension;

- `number`: the field number;

- `type`: the protobuf type, such as `"int32"`, `"string"`, `"message"`
  or `"enum"`;

- `label`: `"optional"`, `"required"` or `"repeated"`;

- `type_name`: the message or enum type's full name, `NA` for scalars;

- `oneof`: the oneof the field belongs to, or `NA`;

- `json_name`: the name in protobuf JSON;

- `presence`: whether the field tracks whether it is set;

- `packed`: whether repeated values are packed on the wire;

- `map`: whether the field is a map;

- `extension`: whether the field is an extension.

## Details

An extension is named by its full name in brackets, as in protobuf's
JSON mapping, for example `"[transit_realtime.trip_descriptor_ext]"`.
Decoded messages use the same names.

## Examples

``` r
pool <- proto_pool()
head(proto_types(pool))
#>                                             name
#> 1                            google.protobuf.Any
#> 2                            google.protobuf.Api
#> 3                      google.protobuf.BoolValue
#> 4                     google.protobuf.BytesValue
#> 5                google.protobuf.DescriptorProto
#> 6 google.protobuf.DescriptorProto.ExtensionRange
#>                               file fields
#> 1        google/protobuf/any.proto      2
#> 2        google/protobuf/api.proto      8
#> 3   google/protobuf/wrappers.proto      1
#> 4   google/protobuf/wrappers.proto      1
#> 5 google/protobuf/descriptor.proto     11
#> 6 google/protobuf/descriptor.proto      3
proto_fields(pool, "google.protobuf.Timestamp")
#>      name number  type    label type_name oneof json_name presence packed   map
#> 1 seconds      1 int64 optional      <NA>  <NA>   seconds    FALSE  FALSE FALSE
#> 2   nanos      2 int32 optional      <NA>  <NA>     nanos    FALSE  FALSE FALSE
#>   extension
#> 1     FALSE
#> 2     FALSE
```
