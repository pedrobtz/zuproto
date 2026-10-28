# zuproto

## Overview

[Protocol Buffers](https://protobuf.dev/) is a binary format for
structured data. gRPC APIs, Kafka topics, transit feeds, telemetry
pipelines and machine-learning datasets all use it. Its bytes mean
nothing without the schema that describes them, and reading them in R
has meant installing the C++ protobuf library and handling each message
as its own object.

zuproto reads and writes any protobuf message in R. It works from the
compiled schema, and turns thousands of messages into one data frame.

- **Any message type, no generated code.** Give zuproto a descriptor
  set, the schema as `protoc --descriptor_set_out` or `buf build` writes
  it, and it decodes and encodes every type in it.
- **Many messages are columns.** A list of messages, a length-delimited
  stream, or a message’s repeated field becomes a data frame, filled
  column by column in C.
- **No system library.** zuproto bundles
  [upb](https://github.com/protocolbuffers/protobuf/tree/main/upb), the
  small C runtime under protobuf’s Python, Ruby and PHP implementations.
  It needs no `libprotobuf`, `protoc` or Abseil, and no other R package.
- **R types where they fit.** Enums are factors, `Timestamp` is
  `POSIXct`, `Duration` is `difftime`, and 64-bit integers can stay
  exact.
- **Careful with untrusted bytes.** Input size, nesting depth, memory
  and rows are all capped, strings are checked as UTF-8, and an
  interrupted decode frees its memory.

## Installation

Install the released version from CRAN:

``` r

install.packages("zuproto")
```

Or the development version from GitHub:

``` r

# install.packages("pak")
pak::pak("pedrobtz/zuproto")
```

## Usage

``` r

library(zuproto)
```

A pool holds the message types zuproto knows. Every pool starts with
protobuf’s well-known types:

``` r

pool <- proto_pool()
pool
#> <proto_pool: 11 files, 61 message types>
```

R values become messages and back. A `Timestamp` is a `POSIXct`, and a
`Struct` is a named list:

``` r

when <- as.POSIXct("2026-10-27 15:36:18", tz = "UTC")
bytes <- proto_encode(when, "google.protobuf.Timestamp", pool)
bytes
#> [1] 08 f2 89 83 d7 06
proto_decode(bytes, "google.protobuf.Timestamp", pool)
#> [1] "2026-10-27 15:36:18 UTC"

bytes <- proto_encode(
  list(station = "Bern", platform = 7, delayed = TRUE),
  "google.protobuf.Struct",
  pool
)
str(proto_decode(bytes, "google.protobuf.Struct", pool))
#> List of 3
#>  $ delayed : logi TRUE
#>  $ platform: num 7
#>  $ station : chr "Bern"
```

Protobuf’s JSON mapping goes both ways:

``` r

proto_to_json(bytes, "google.protobuf.Struct", pool)
#> [1] "{\"platform\":7,\"delayed\":true,\"station\":\"Bern\"}"
```

Many messages become a data frame. A descriptor set is itself a protobuf
message, a `FileDescriptorSet`, so the one zuproto ships for the
well-known types can be read as a table. Each row is a `.proto` file,
with the number of message types it defines at the top level:

``` r

wkt <- system.file("descriptors", "wkt.binpb", package = "zuproto")
files <- proto_decode_df(
  wkt,
  "google.protobuf.FileDescriptorSet",
  pool,
  field = "file"
)
data.frame(
  name = files$name,
  messages = vapply(files$message_type, NROW, integer(1))
)
#>                                    name messages
#> 1             google/protobuf/any.proto        1
#> 2  google/protobuf/source_context.proto        1
#> 3            google/protobuf/type.proto        5
#> 4             google/protobuf/api.proto        3
#> 5      google/protobuf/descriptor.proto       23
#> 6        google/protobuf/duration.proto        1
#> 7           google/protobuf/empty.proto        1
#> 8      google/protobuf/field_mask.proto        1
#> 9          google/protobuf/struct.proto        3
#> 10      google/protobuf/timestamp.proto        1
#> 11       google/protobuf/wrappers.proto        9
```

Your own schema goes in the same way. Compile it once with `protoc` or
`buf`, then load the descriptor set. Here it is with the live trip
updates for Switzerland’s public transport, in the GTFS Realtime format.
The code is not run here; the output is from 27 October 2026:

``` r

pool <- proto_pool("gtfs-realtime.binpb")
trips <- proto_decode_df(
  "trip-updates.binpb",
  "transit_realtime.FeedMessage",
  pool,
  field = "entity"
)
table(trips$trip_update$trip$schedule_relationship)[1:4]
#>
#>   SCHEDULED       ADDED UNSCHEDULED    CANCELED
#>       15187         245           0         144
```

Every function that converts a message takes the value, the message
type’s full name and the pool, in that order.

## Learn more

- [Live Swiss trains with GTFS
  Realtime](https://pedrobtz.github.io/zuproto/articles/gtfs-rt.html)
  works through a real feed: compiling the schema, fetching the data,
  and turning trips and stop delays into tables.
- The [reference index](https://pedrobtz.github.io/zuproto/reference/)
  lists every function.
  [`?proto_decode`](https://pedrobtz.github.io/zuproto/reference/proto_decode.md)
  maps protobuf types to R types,
  [`?proto_decode_df`](https://pedrobtz.github.io/zuproto/reference/proto_decode_df.md)
  says how fields become columns, and `?zuproto-conditions` lists the
  errors and warnings.

## Related work

zuproto bundles upb and `utf8_range` from
[protobuf](https://github.com/protocolbuffers/protobuf) `v36.2`. Its CI
runs protobuf’s conformance test suite, with the tests zuproto is
expected to fail listed and explained, and the test fixtures come from
Python’s `protobuf`.
[RProtoBuf](https://CRAN.R-project.org/package=RProtoBuf) binds the C++
protobuf library and handles each message as an object.
[protolite](https://CRAN.R-project.org/package=protolite) serialises a
fixed set of schemas: R objects, GeoJSON and Mapbox vector tiles.
