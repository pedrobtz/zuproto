# Build information

Reports the zuproto version and the Protocol Buffers release whose upb
runtime is bundled.

## Usage

``` r
zuproto_info()
```

## Value

A list of class `zuproto_info` with elements:

- `version`: zuproto's version.

- `protobuf`: the protobuf release tag upb was vendored from, such as
  `"v36.2"`.

- `protobuf_commit`: that tag's commit.

## Examples

``` r
zuproto_info()
#> <zuproto_info>
#> zuproto:  0.0.0.9000
#> upb:      protobuf v36.2 (2c74169)
```
