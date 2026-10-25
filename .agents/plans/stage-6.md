# Stage 6 — JSON, Any and 64-bit integers: implementation plan

> Written after the fact; the stage followed the roadmap and design §5,
> §6.1 and §6.3, with three maintainer decisions taken during it.

**Decisions:** `int64 = "zuint"` deferred (zuint not on CRAN); JSON as R
values through zujson in `Suggests`, upb keeping the protobuf JSON
mapping; no C API between zujson and zuproto for now.

1. Shim: upb JSON encode (measure, then write) and decode.
2. `zpb_to_json()`, `zpb_from_json()` in `src/zpb_decode.c`, with the
   capped arena; `from_json` re-encodes deterministically.
3. `int64 = "integer64"`: bits in the double, `INT64_MIN` and
   `uint64 > INT64_MAX` as NA with a warning; encode reads the bits.
4. `R/json.R`: `proto_to_json(parse =)`, `proto_from_json()` taking text
   or an R value, `proto_unpack_any()`.
5. Tests: JSON round trip gives each fixture's bytes; canonical mapping
   spot checks; errors; zujson round trip; integer64 decode, frames,
   encode.
