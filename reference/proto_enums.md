# Enum values

Lists the values of one enum type in a pool: the levels a decoded enum
field takes as a factor, with their numbers.

## Usage

``` r
proto_enums(pool, type)
```

## Arguments

- pool:

  A pool from
  [`proto_pool()`](https://pedrobtz.github.io/zuproto/reference/proto_pool.md).

- type:

  An enum type's full name, such as `"google.protobuf.NullValue"`.
  [`proto_fields()`](https://pedrobtz.github.io/zuproto/reference/proto_types.md)
  gives it as a field's `type_name`.

## Value

A data frame with one row per value, in definition order, and columns
`name` and `number`. An alias (`allow_alias`) is a row of its own with
the number it shares. R has no integer for -2^31, so that number is
`NA`, with a `zuproto_precision_loss` warning.

## Examples

``` r
pool <- proto_pool()
proto_enums(pool, "google.protobuf.Field.Kind")
#>             name number
#> 1   TYPE_UNKNOWN      0
#> 2    TYPE_DOUBLE      1
#> 3     TYPE_FLOAT      2
#> 4     TYPE_INT64      3
#> 5    TYPE_UINT64      4
#> 6     TYPE_INT32      5
#> 7   TYPE_FIXED64      6
#> 8   TYPE_FIXED32      7
#> 9      TYPE_BOOL      8
#> 10   TYPE_STRING      9
#> 11    TYPE_GROUP     10
#> 12  TYPE_MESSAGE     11
#> 13    TYPE_BYTES     12
#> 14   TYPE_UINT32     13
#> 15     TYPE_ENUM     14
#> 16 TYPE_SFIXED32     15
#> 17 TYPE_SFIXED64     16
#> 18   TYPE_SINT32     17
#> 19   TYPE_SINT64     18
```
