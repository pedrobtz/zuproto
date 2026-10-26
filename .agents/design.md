# RFC 0010: `zuproto`, Protocol Buffers in R with upb

Adopted from [RFC 0010](https://github.com/pedrobtz/packages/blob/main/rfcs/started/0010-zuproto-protocol-buffers.md)
on 2026-10-24. From here on this file is authoritative; the RFC is history.

- **Status:** Proposed. Merging this file adopts the design as the starting
  point for the package's own `.agents/design.md`; each decision in section
  17 stays the maintainer's until the package repository records it.
- **Date:** 2026-10-09.
- **Packages:** `zuproto` (not yet created; name unchecked); vendors upb
  and `utf8_range` from the protobuf repository; `zuint` (RFC 0009) in
  `Suggests` for 64-bit fields.
- **Source:** the protobuf repository at `main` commit `6559a9f`
  (2026-10-09, `version.json` "37-dev"; the latest release tag is
  `v36.2`): `upb/README.md`, `upb/BUILD` (the `gen_amalgamation`,
  `gen_php_amalgamation` and `gen_ruby_amalgamation` targets), the
  checked-in `ruby/ext/google/protobuf_c/ruby-upb.{c,h}` and
  `php/ext/google/protobuf/php-upb.{c,h}`, and `extconf.rb`; the
  exported APIs of `RProtoBuf` and `protolite`, which zuproto sits beside;
  the alternatives review that proposed this package ("interesting but
  harder: upb is designed for language bindings, but its low-level C API
  changes frequently; vendor a pinned version and keep the initial scope
  narrow"). The reading was of source, not of a running build; section
  14 says what the first stage measures.

## 1. What zuproto is

`zuproto` decodes and encodes Protocol Buffers messages in R through upb,
the small C runtime that already sits under protobuf's Python, Ruby and
PHP implementations. It works from **descriptor sets**, not generated
code: give it the compiled schema (`protoc --descriptor_set_out` or
`buf build`), and it reads and writes any message type in it, as R lists
for one message and as **data frames for many**.

It is a *format* package, like `zucbor` and `zumsgpack`, with one
difference the rest of this RFC follows from: protobuf bytes mean
nothing without a schema, so every call names a message type in a
descriptor pool.

The one-line statement that governs every decision below:

> **Decode protobuf bytes into upb's arena first, build R values only
> from a complete, valid message, and turn many messages into columns,
> not into many objects.**

## 2. Scope

**In v0.1.0:**

- Descriptor pools loaded from serialised `FileDescriptorSet`s (raw
  vector, file or connection), with the well-known types bundled.
- Decoding one message to a named list; encoding a named list to bytes.
- Decoding many messages (a list of raw vectors, or a length-delimited
  stream) to a **data frame**, column by column.
- Every proto2, proto3 and editions field kind upb supports: scalars,
  enums, strings, bytes, nested messages, `repeated`, `map`, `oneof`,
  presence (`optional`), defaults, unknown fields kept on request.
- Well-known types: `Timestamp`, `Duration`, wrappers, `Struct`/`Value`/
  `ListValue`, `Any` (packed bytes plus type URL), `FieldMask`, `Empty`.
- Protobuf JSON (canonical mapping) in both directions, through upb.
- Deterministic encoding (upb's `kUpb_EncodeOption_Deterministic`).

**Later, when asked:**

- Loading `.proto` text by calling `protoc` or `buf` from `PATH`
  (`proto_compile()`), since upb cannot parse `.proto` files.
- A native `.proto` parser, which would remove that external step
  (a separate RFC).
- gRPC server reflection as a descriptor source.
- Text-format output (upb's `upb/text`), for debugging.
- Parallel decoding of many messages into upb arenas, with serial R
  construction.

**Never:**

- Generated R code per message type. Reflection is fast in upb (its
  README: runtime-loaded messages parse as fast as compiled-in ones),
  and generated code is exactly what makes `RProtoBuf` heavy.
- A gRPC client. That is a transport, not a format.
- Text-format parsing: upb does not implement it.

## 3. Position in the `zu*` family

The rows for `zu-family.md` (alignment R1):

| | zuproto |
| --- | --- |
| Role | format |
| R prefix | `proto_` |
| Info function | `zuproto_info()` |
| Root condition class | `zuproto_error` |
| Public C prefix | none; internal `zpb_` / `ZPB_` |
| From C | no C API |
| Hides symbols | yes, from Stage 0 (R3) |
| Vendored code | upb (amalgamation) and `utf8_range` |
| `Depends: R` | 4.1 (R2) |
| Language | en-GB (R2) |

The `zpb_` prefix is unused in this repository's documents on
2026-10-09. Stage 0 checked it on 2026-10-24: a GitHub code search over
every `pedrobtz` repository finds `zpb_` only in this design's RFC.

**Relationships, as decided rather than as hoped:**

- **`zuint`** (RFC 0009): `int64`, `uint64`, `sint64`, `fixed64` and
  `sfixed64` fields map to zuint types when `int64 = "zuint"`, which is
  the lossless choice. **Deferred to after 0.1.0** (decided 2026-10-25,
  Stage 6): zuint is not yet on CRAN, and suggesting an unreleased
  package is a NOTE; `int64 = "character"` is the exact option until
  then. `Suggests` only; the default is `"double"` with a
  warning on loss, as `zucbor` and `zumsgpack` treat big integers.
- **`bit64`**: `int64 = "integer64"` for signed 64-bit fields, for users
  already in that ecosystem. bit64's `NA` is `-2^63`, so that value, and
  `uint64` values above `2^63 - 1`, decode as `NA` with a
  `zuproto_precision_loss` warning.
- **`zujson`** (`Suggests`, decided 2026-10-25): upb does the protobuf JSON
  mapping; zujson turns the text into R values (`proto_to_json(parse =
  TRUE)`) and R values into text (`proto_from_json()` given a list). No C
  API between them: the saving (one copy of the text) does not pay for a
  hard dependency and a shared interface; revisit if `parse = TRUE` shows
  up in a profile.
- **`zucbor` and `zumsgpack`** are the templates for conditions,
  limits, interrupts and the data-frame shape, not for the decoder:
  upb is the decoder.
- **`zufast` and `zubin`** are not used. upb validates UTF-8 through
  `utf8_range` and encodes into its own arena, so neither provider has a
  job here.
- **`zufuzz`** runs the decode fuzz target in CI (§15).

**Consumers.** None named. The users are R clients of systems that
speak protobuf: gRPC and Connect APIs read through `httr2`/`zuhttp`,
Kafka topics with protobuf payloads, Google Cloud and Bigtable exports,
OpenTelemetry (OTLP) payloads, TensorFlow `Example` records, and
`.binpb` files from Python or Go.

**What exists elsewhere.**

- `RProtoBuf` (CRAN; Eddelbuettel and co-authors) binds the C++ protobuf
  library and needs a system `libprotobuf` and `protoc`. Since protobuf
  v22 that library also needs Abseil, a large, version-sensitive C++
  dependency, which makes static and air-gapped builds hard. Each message
  becomes an S4 object backed by a C++ message, so many messages mean
  many objects.
- `protolite` (CRAN; Ooms) is light but serialises a fixed set of
  schemas (R objects, GeoJSON and Mapbox vector tiles), not arbitrary
  messages; it also links `libprotobuf`.

The gap: arbitrary messages, no system library, and many messages as
columns. The cost of filling it is upb's unstable C API, which §9 turns
into a vendoring discipline.

## 4. Architecture

```text
descriptor set (raw / file)                 message bytes
      |                                            |
      v                                            v
  pool  (src/zpb_pool.c)                     decode (src/zpb_decode.c)
   - parse FileDescriptorSet in an arena      - upb_Message_New in a
   - upb_DefPool_AddFile per file,              per-call arena
     dependencies first                       - upb_Decode with depth,
   - well-known types pre-loaded                size and UTF-8 options
   - external pointer, finalised              - status checked; on
      |                                         failure, no R object
      |                                            |
      +------------------> message def ------------+
                                                   v
                                     build (src/zpb_build.c, R)
                                       - one message: walk fields by
                                         reflection into a named list
                                       - many messages: plan columns
                                         from the message def, then fill
                                         each column across messages
                                                   |
                                                   v
                                               R value

  R value --> zpb_fill.c (list to upb message, type-checked)
          --> upb_Encode (deterministic) --> raw vector
```

All upb calls go through one internal header, `src/zpb_upb.h`, the
**shim** of §9.3. No other file includes the vendored header. When a
re-vendor changes an upb signature, the shim is the one file to edit.

The decode path never calls R while upb is on the C stack: upb uses
`setjmp`/`longjmp` internally for decoder errors, and an R error
unwinding through those frames would skip upb's cleanup. Building
starts only after `upb_Decode` has returned `kUpb_DecodeStatus_Ok`.

## 5. Public R API (complete v0.1.0 surface)

```r
# descriptor pools
pool <- proto_pool()                     # well-known types only
pool <- proto_pool("schema.binpb")       # plus a FileDescriptorSet
proto_pool_add(pool, raw_or_path)
proto_types(pool)                        # data frame of message types
proto_fields(pool, "pkg.Msg")            # data frame of fields

# one message
proto_decode(raw, "pkg.Msg", pool)       # named list
proto_encode(x, "pkg.Msg", pool)         # raw vector

# many messages
proto_decode_df(list_of_raw, "pkg.Msg", pool)    # data frame
proto_read_delimited(path_or_raw, "pkg.Msg", pool, each = NULL)
proto_write_delimited(df_or_list, "pkg.Msg", pool, path = NULL)

# protobuf JSON
proto_to_json(raw, "pkg.Msg", pool)
proto_from_json(json, "pkg.Msg", pool)   # raw vector

zuproto_info()
```

### Decode arguments

| Argument | Default | Meaning |
| --- | --- | --- |
| `int64` | `"double"` | `"zuint"`, `"integer64"`, `"character"` |
| `enums` | `"factor"` | `"integer"`, `"character"` |
| `defaults` | `TRUE` | unset proto3 scalars as defaults, not `NULL` |
| `unknown` | `"drop"` | `"keep"`: attribute `proto_unknown` (raw) |
| `bytes` | `"raw"` | `"base64"` |
| `max_size` | 64 MiB | input bytes per message |
| `max_depth` | 100 | nesting, upb's own default |
| `max_rows` | 1e7 | messages per data frame |

### Encode arguments

`deterministic = TRUE` (sorted map entries, upb's option);
`unknown = TRUE` writes back an `proto_unknown` attribute if present;
`check_required = TRUE` for proto2 `required` fields.

## 6. Protobuf to R

### 6.1 Scalars

| Protobuf | R |
| --- | --- |
| `double`, `float` | double |
| `int32`, `sint32`, `sfixed32` | integer |
| `uint32`, `fixed32` | double (exact; above `.Machine$integer.max`) |
| 64-bit integer kinds | per `int64 =` (§5) |
| `bool` | logical |
| `string` | character, UTF-8 |
| `bytes` | raw (list column in data frames) |
| enum | factor with the enum's value names as levels |

An enum value not in the definition (open enums, proto3) becomes `NA`
with a `zuproto_unknown_enum` warning under `enums = "factor"`, and
stays the number under `"integer"`.

Decided 2026-10-25 (Stage 3): an `int32`, `sint32` or `sfixed32` value of
`-2^31` is `NA_integer_` with a `zuproto_precision_loss` warning, since R
reserves that bit pattern for `NA`; a `string` holding a NUL byte is a
`zuproto_unrepresentable` error naming the field. Warnings are raised
once per call, with the count in `n`.

Found by `fuzz_build` after Stage 7 (2026-10-26): a wire `double` whose
bits are R's `NA` read as `NA`; every decoded NaN is now R's `NaN`, so a
decoded double is never `NA`. Timestamp and Duration seconds beyond 2^53
count as precision loss, as 64-bit integers do.

### 6.2 Messages, repeated, maps, oneofs

| Protobuf | One message | Data-frame column |
| --- | --- | --- |
| nested message | named list | data-frame column (nested) |
| `repeated` scalar | atomic vector | list column of vectors |
| `repeated` message | list of lists | list column of data frames |
| `map<K, V>` | named list or vector | list column |
| `oneof` | the set member only | a column per member, plus `<oneof>_case` |
| unset with presence | `NULL` | `NA` |

Map keys of integer kinds become names through their decimal form (always
exact, whatever `int64` says); `bool` keys become `"false"` and `"true"`.
Entries are **sorted by key** (decided 2026-10-25): numerically for
integer keys, false before true, by bytes for strings, since upb keeps no
wire order. Repeated `Timestamp`, `Duration` and wrapper fields, and map
values of those types, become vectors rather than lists.

### 6.3 Well-known types

| Type | R |
| --- | --- |
| `Timestamp` | `POSIXct`, UTC; sub-microsecond digits rounded |
| `Duration` | `difftime` in seconds |
| wrappers (`Int32Value` …) | the scalar; unset: left out, `NA` in data frames |
| `Struct`, `Value`, `ListValue` | named list, scalar, list, as JSON |
| `Any` | list(`type_url`, `value` raw); `proto_unpack_any()` decodes it |
| `FieldMask` | character vector of paths |
| `Empty` | `list()` |

### 6.4 Data frames

Decided in Stage 5 (2026-10-25): with `field = "<name>"`, the input is
one message and the rows are the elements of that repeated message field
(question 6); `<oneof>_case` columns hold the member set; every extension
the pool knows for the type has a `[pkg.ext]` column; a message field
that no row sets is an all-`NA` column, which is where a recursive
type's columns end; a message type with no fields (`Empty`) is a list
column, so set and unset stay distinct. Each failing message's
condition carries `index`.

`proto_decode_df()` decodes every message into one arena first, then
builds column by column from the message definition: one pass over the
messages per column, scalar columns written straight into their R
vectors, strings interned once per value through `Rf_mkCharLenCE`. This
is the core of the package's case over `RProtoBuf`, which would build one
S4 object per message.

## 7. R to protobuf

`proto_encode()` walks the message definition, not the list: every
field present in `x` is checked against the field's kind and filled;
names in `x` that the message does not define are a
`zuproto_unknown_field` error (option `extra = "ignore"`). Doubles to
integer kinds must be whole and in range. `NA` encodes as unset, and is
an error for a field without presence in proto2 `required`.

Decided in Stage 4 (2026-10-25), where §7 left it open: a map key given
twice, a second member of a oneof, `NA` inside a repeated field, and a
`Timestamp` or `Duration` whose seconds an `int64` cannot hold are
`zuproto_type_mismatch`, each carrying the field's `path` (revised in
Stage 7: the 0001–9999 and ±10000-year ranges belong to the JSON
mapping, which upb enforces, and refusing them on binary encode broke
decode → encode for values the binary format allows); `bytes` fields
take raw vectors only; a `Timestamp` before 1970 keeps nanos
non-negative, a `Duration` gives its nanos the seconds' sign. Unknown
fields go back through upb's internal add-unknown call, which the shim
spells out by name, since upb has no public one.

`proto_write_delimited()` takes a data frame whose columns follow §6.2
and writes one message per row.

### 7.1 Known lossy conversions

- `Timestamp` nanoseconds beyond `POSIXct` precision.
- 64-bit integers under `int64 = "double"` beyond 2^53 (warned).
- Unknown fields under `unknown = "drop"` (the default).
- Field order on the wire: encoding is canonical by field number, so a
  round trip need not be byte-identical to a non-canonical input.

## 8. Descriptor pools

- A pool is an external pointer to a `upb_DefPool` and its arena,
  finalised. Pools are immutable to R code except through
  `proto_pool_add()`.
- `proto_pool_add()` parses a `FileDescriptorSet` with
  `google_protobuf_FileDescriptorSet_parse()` and adds files in
  dependency order with `upb_DefPool_AddFile()`, reporting a missing
  import by file name. A file already in the pool with identical bytes
  is skipped; with different bytes it is a `zuproto_pool_conflict`.
- The well-known types ship as one serialised descriptor set in
  `inst/descriptors/wkt.binpb`, generated at vendoring time by `protoc`
  from the pinned release's `.proto` files: the ten well-known types and
  `descriptor.proto`, which schemas with custom options import. Its
  SHA-256 is in `src/vendor/PROVENANCE`, and `tools/verify-vendor` checks
  it there rather than in a test (base R before 4.5 has no SHA-256) or by
  regenerating it (another `protoc` may encode the same files
  differently). A test checks that every well-known type loads.
- A pool lists the files added to it, with their bytes, so a set is
  checked whole (conflicts, missing imports) before any of it is added,
  and files are added in dependency order whatever order the set lists
  them in.
- **Extensions** (§18 question 7, decided 2026-10-25): upb registers a
  file's extensions when the file is added, so pools need nothing more.
  An extension is named by its bracketed full name, `[pkg.ext]`, as in
  protobuf's JSON mapping: in `proto_fields()` (Stage 2), as the name of
  a set extension in a decoded list (Stage 3), as its own data-frame
  column (Stage 5), and as an accepted name when encoding (Stage 4).
- upb's README warns its descriptor validation is less exhaustive than
  `protoc`'s. zuproto treats descriptor sets as **trusted input** and
  says so in the documentation; message bytes are untrusted.
- Editions: upb applies the compiled-in feature-set defaults; zuproto
  exposes nothing about editions in 0.1.0 and tests that an editions
  descriptor loads and decodes.

## 9. The vendored library, as zuproto uses it

### 9.1 What is vendored

upb publishes no releases and calls its C API and ABI unstable (its
README). The protobuf repository does carry **checked-in
amalgamations**, one `.c` and one `.h` each, for Ruby and PHP, built
from `upb/BUILD`'s amalgamation targets. The Ruby one
(`ruby-upb.c`, about 706 KB; `ruby-upb.h`, about 952 KB at `6559a9f`)
contains the wire decoder and encoder, reflection, mini tables, the
descriptor messages and JSON, which is everything §2 needs. It does
not contain text format.

zuproto vendors, at a **pinned release tag** (`v36.2`, commit
`2c74169`, since Stage 1 on 2026-10-25), into `src/vendor/` (the
family's layout and r-actions' default, not the `src/upb/` first
proposed):

- `ruby/ext/google/protobuf_c/ruby-upb.{c,h}` as `src/vendor/upb/`,
  under their upstream names, so the `.c` file's own `#include` needs
  no patch;
- `third_party/utf8_range/` (`utf8_range.{c,h}`, the two `.inc` files it
  includes, and its licence) as `src/vendor/utf8_range/`;
- protobuf's licence as `src/vendor/upb/LICENSE`; both licences are
  summarised in `inst/COPYRIGHTS`.

`tools/upb-files.txt` lists the file set. `tools/vendor-upb <tag>`
fetches those files at the tag's commit, applies `tools/patches/` and
writes `src/vendor/PROVENANCE` with the tag, the commit and each
upstream file's SHA-256. `tools/verify-vendor` re-derives the tree and
fails on any difference; `--canary` leaves the first patch out and
requires that to fail. The `vendor` workflow runs it on every push.
`wkt.binpb` (§8) is generated in Stage 2.

**Ruby or PHP (§18 question 4), measured 2026-10-25 at v36.2:** the PHP
amalgamation compiles to an 8% smaller object (1.19 MB against 1.30 MB
unstripped, macOS clang) and lacks 8 `-Wextra` field-initialiser
warnings, which CRAN does not use. Both need the same patches. Ruby is
kept: D2's reason (its `extconf.rb` shows the exact file set) stands,
and it is the one every CI leg measured.

### 9.2 Patches

Kept as files in `tools/patches/`, applied in order. Revised 2026-10-25
after the Stage 1 measurement (pull request #15): the first proposal
was two patches, and the full CI profile on unpatched v36.2 and the
runs after it showed four are needed, plus one define; Stage 3's
sanitizer runs added a fifth and Stage 7's fuzzing a sixth, seventh and
eighth.
None touches decoder logic.

1. `0001-no-stdio.patch`: `_upb_UnreachableFailure()` (`fprintf` to
   `stderr`, then `abort()`) is compiled only without `NDEBUG`, which
   `R CMD INSTALL` always defines, so nothing calls it; and the `fprintf`
   on `_upb_DefPool_LoadDefInitEx()`'s error path, which loads
   compiled-in descriptors zuproto never uses, is removed. CRAN's
   compiled-code check otherwise reports `stderr` and `abort`.
2. `0002-no-pragmas.patch`: every `#pragma` goes: a `GCC diagnostic`
   block silencing false `-Warray-bounds` and `-Wstringop-*` warnings
   (`R CMD check`: "pragma(s) suppressing important diagnostics"), and
   MSVC-only `section` and `intrinsic` lines ("non-portable pragma(s)").
   Without them Rtools' gcc reported the false warnings, as significant
   ones, when it inlined `_upb_MiniTableField_DataCopy` into callers;
   the patch therefore also makes upstream's `UPB_INLINE_IF_NOT_GCC`
   (already non-inline on gcc) `noinline`, so gcc never sees them.
3. `0003-pedantic.patch`, made by `tools/make-pedantic-patch`: the 21
   generated enum tables of `descriptor.proto` initialise
   `upb_MiniTableEnum`'s flexible array member, which gcc and clang
   report under CRAN's `-pedantic`. Each table is stored in a fixed-size
   struct with the same layout, and a macro keeps its name as a
   `upb_MiniTableEnum`; no code that reads the tables changes. The same
   patch drops one extra `;` after a function in the header.
4. `0004-mingw-printf-format.patch`: on MinGW, `UPB_PRINTF` checks
   formats as `gnu_printf`. Rtools' gcc reads plain `printf` as
   Microsoft's, which has no `%zu`, and warned on two error messages.
5. `0005-flexible-str.patch` (Stage 3): the string type holding proto2
   default values used the `char str[1]` struct hack, and UBSan reported
   its reads past index 0 as out of bounds when a schema has a string
   `[default = …]`. It becomes a C99 flexible array member, and its two
   allocations add the byte the NUL terminator needs.
6. `0006-any-empty-url.patch` (Stage 7, found by `fuzz_decode`): upb's
   JSON encoder computed `data + size` on an `Any`'s empty `type_url`,
   whose data is then `NULL`, before checking for the empty URL; `NULL +
   0` is undefined in C and UBSan reports it. The check moves first.
   Reported upstream as protocolbuffers/protobuf#31030.
7. `0007-json-any-arena-leak.patch` (Stage 7, found by `fuzz_decode`
   under LeakSanitizer in CI): when JSON encoding fails after an `Any` has
   made upb's arena (its packed bytes do not decode, or a later error in
   the message), upb returned from its `setjmp` error branch without
   freeing that arena, so `proto_to_json()` leaked on every such call. The
   error branch frees it too. Reported upstream as
   protocolbuffers/protobuf#31031.
8. `0008-json-nanos-range.patch` (Stage 7, found by `fuzz_decode` under
   UBSan in CI): upb's JSON encoder negated a `Duration`'s `nanos`
   without checking its range, undefined for `-2^31`, and never checked a
   `Timestamp`'s. Both now refuse `nanos` outside protobuf's range, as the
   JSON mapping requires. Reported upstream as
   protocolbuffers/protobuf#31032.

No `assert()` patch: `R CMD INSTALL` defines `NDEBUG`, so `UPB_ASSERT`
is already empty. `__USE_MINGW_ANSI_STDIO=1` in `src/Makevars` gives
Rtools the C99 `printf` family, so the `%zu` that patch 4 lets through
is also what runs.

A patch that touches decoder logic is still a reason to stop and
report upstream instead.

### 9.3 The shim

`src/zpb_upb.h` declares the dozen upb operations zuproto uses, as
`static inline` wrappers: create and free arenas; parse a descriptor
set; add a file; find a message; create, decode and encode a message;
iterate set fields; get and set by field definition; array and map
access; JSON encode and decode. It also re-exports only the enums
zuproto reads. `tools/verify-vendor` fails on any upb include or symbol
outside the shim, since the installed package a test sees has no `src/`.

### 9.4 Re-vendoring

- Cadence: when a protobuf release fixes a security issue in upb, or
  twice a year otherwise; never mid-stage.
- Procedure: run `tools/vendor-upb <tag>`; if `0003-pedantic.patch` no
  longer applies, regenerate it with `tools/make-pedantic-patch`; run
  `tools/verify-vendor`; fix the shim until it compiles; run the full CI
  profile and the conformance job (§15); record the tag in `NEWS.md`.
  The `vendor-upstream` workflow opens an issue when protobuf releases a
  newer tag.
- Budget: the API churn the review warned about is real, so the shim
  stays small and the patches stay few; both were measured in Stage 1
  and are re-measured on every re-vendor.

## 10. Input sources and delimited streams

- A message is a raw vector; `proto_decode()` reads a path or a
  connection up to `max_size + 1` bytes and refuses beyond.
- A delimited stream is varint length plus message, back to back: the
  framing of Java's `writeDelimitedTo`, Python's `_VarintBytes` helpers,
  Kafka tooling and many `.pb` log files. `proto_read_delimited()` reads
  it in memory bounded by `max_size` and returns a data frame, or calls
  `each(df)` per chunk of `chunk_rows` messages.
- No other framing in 0.1.0 (gRPC's 5-byte prefix is a later option).

## 11. Errors

Every condition inherits `zuproto_error`: `zuproto_invalid_argument`,
`zuproto_parse_error` (upb's decode status, with `status` naming upb's
enumerator and `index` the message's position in a batch),
`zuproto_invalid_utf8`, `zuproto_missing_required`,
`zuproto_unknown_type`, `zuproto_unknown_field`,
`zuproto_type_mismatch` (encode), `zuproto_unrepresentable` (a decoded
value R cannot hold, added in Stage 3), `zuproto_pool_error` and
`zuproto_pool_conflict`, `zuproto_json_error`, `zuproto_limit_error`
with `zuproto_depth_limit`, `zuproto_size_limit`, `zuproto_row_limit`,
`zuproto_io_error`, and `zuproto_internal_error`. Warnings:
`zuproto_unknown_enum`, `zuproto_precision_loss`.

## 12. Limits and hostile input

- `max_size` (64 MiB) per message, checked before upb sees the bytes.
- `max_depth` passed to upb through `upb_DecodeOptions_MaxDepth()`;
  default 100, upb's own `kUpb_WireFormat_DefaultDepthLimit`. upb counts
  levels below the top-level message, so 100 accepts 101 messages, one
  inside the next (measured in Stage 3); a map entry is a level too.
  `max_depth` is at most 1000: upb's decoder recurses once per level,
  and the C stack ran out at about 5000 on an 8 MB stack. The encoder
  takes the same 1000 levels, fixed, so whatever decodes re-encodes
  (upb's default of 100 had made a deeper message "out of memory",
  #27); deeper is `zuproto_depth_limit`. upb's JSON parser stops at 64
  levels on its own, a `zuproto_json_error`, so `proto_from_json()`
  never reaches the encoder's limit (#48).
- `max_rows` (1e7) per data frame, and an arena byte ceiling per call,
  enforced by a counting allocator handed to `upb_Arena_Init`, so a small
  input that expands cannot exhaust memory. The ceiling is derived from
  the schema, which is trusted, not set by the user: input bytes times
  (the largest struct reachable from the type + 64), plus, per message,
  its struct + 256, plus 1 MiB (`zpb_arena_ceiling()` in the shim). Two
  wire bytes (a tag and a zero length) can create one struct, a scalar
  expands at most 8×, arrays and map tables at most double that, so no
  legitimate input reaches it. *Revised 2026-10-26 (#26):* the first
  ceiling, 4 × the input, refused legitimate input: 10^6 packed zeros,
  and batches of a few dozen small messages. The `arena_limit` option is
  gone, and the `arena_limit` path of `zuproto_size_limit` is now reachable
  only through hostile input past the schema's factor, not from R tests
  (§15).
- `google.protobuf.Any` on the way to JSON: upb's JSON encoder decodes
  each packed Any afresh, with no depth limit, no UTF-8 check and an
  uncapped arena. `zpb_check_any()` decodes every Any first, with the
  depth left, UTF-8 validation and the capped arena (raised by each Any's
  own ceiling), so a chain of Anys is `zuproto_depth_limit`, not a stack
  overflow (#25).
- UTF-8 is validated for every `string` field
  (`kUpb_DecodeOption_AlwaysValidateUtf8`), not only proto3 ones.
- Interrupts are checked between messages in batch and stream decoding,
  and every 65,536 rows while building columns; never inside upb.

## 13. Memory model

- Each decode call owns one `upb_Arena`, held by a finalised external
  pointer from the moment it is created, so an interrupt or allocation
  failure during the R build phase frees it through the finaliser; on
  success it is freed eagerly.
- Pools own their arena for their lifetime.
- No upb pointer is stored in an R object except through those external
  pointers; strings are copied into `CHARSXP`s, never aliased.
- Encoding builds the upb message in a fresh arena and copies the
  encoded bytes into a raw vector before the arena is freed.

## 14. Build, portability and CRAN

- C99 for zuproto's own code under the family's lint flags. The
  vendored amalgamation compiles with no warning silenced at all: the
  §9.2 patches remove what CRAN's flags report, since CRAN rejects
  `-Wno-` overrides and suppressing pragmas.
- `DESCRIPTION`: no `LinkingTo`, no `Imports`; `Suggests: bit64,
  testthat, withr, zujson` (zuint joins when it is on CRAN, Stage 6).
  `SystemRequirements` empty: no system protobuf.
- `src/Makevars`: `PKG_CFLAGS = $(C_VISIBILITY)`, the amalgamation and
  `utf8_range` built in, `R_init_zuproto` the only export.
- Measured in Stage 1 (2026-10-25, v36.2):
  - **Unpatched**, the full CI profile (#15) failed every `R CMD check`
    leg on three WARNINGs (§9.2) and nothing else. ASan, UBSan (no
    runtime errors), valgrind (no errors or leaks), gctorture, rchk,
    `-fanalyzer`, LTO (no type mismatches) and rcnst were clean.
    Windows built and linked: upb's linker arrays need no patch on
    MinGW.
  - **C standard:** no `_Thread_local`; the amalgamation builds under
    R's default standard on every leg, including Windows R-devel.
  - **Patched**, locally on macOS (Apple clang 17, `--as-cran`,
    `-Wall -pedantic`): no compiler warning; `R CMD check` with only the
    "New submission" NOTE; compile time about 5 s; shared object 297 KB;
    tarball 254 KB, well under CRAN's 5 MB guideline.
  - **Patched, full CI profile**
    ([run 40165245441](https://github.com/pedrobtz/zuproto/actions/runs/40165245441)):
    every leg green, including
    both Windows legs, the `-pedantic` containers, ASan, UBSan, valgrind,
    gctorture, rchk and LTO. Each `R CMD check` leg finished in 1.5 to
    2.5 minutes.

## 15. Testing

- **Fixtures from other implementations, never by hand.**
  `tools/make-fixtures.py` writes messages with Python's `protobuf` (a
  pinned version, itself on upb) and with `protoc --encode` for a test
  schema that covers every field kind, presence, maps, oneofs, packed
  and unpacked repeated fields, editions, and every well-known type. A
  manifest records each file's source and SHA-256.
- **The protobuf conformance suite.** `conformance_test_runner` drives a
  testee over stdin/stdout; an R testee script built on zuproto runs the
  binary and JSON suites in a CI job, against a recorded list of
  expected failures that may only shrink.
- **Round trip as a property**: decode → encode → decode is identical
  for every fixture; encode → decode is identical for generated R values
  of every mapping row in §6.
- **Data frames against single messages**: `proto_decode_df()` equals
  `proto_decode()` row by row, for every fixture.
- **Fuzzing** with `zufuzz`: a decode target over a fixed pool, under
  ASan and UBSan, seeded from every fixture; the canary must crash
  first.
- **Hostile inputs**, each a permanent regression: a length prefix of
  2^31 with three bytes after it; nesting at depth 101; invalid UTF-8 in
  a proto3 and in a proto2 `string`; a packed repeated field claiming
  10^9 elements; a delimited stream ending inside a varint; a
  descriptor set with a missing import and one with a name conflict.
- **Shim audit**: no upb symbol is used outside `zpb_upb.h`.
- Tests are self-sufficient, pass under `shuffle = TRUE`, and the CRAN
  suite runs in under 15 s; the conformance and fuzz jobs are CI only.

**As built in Stage 7 (2026-10-25).** The conformance testee
(`tools/conformance/`) routes every payload through `proto_decode()` and
`proto_encode()`, so the suite tests the R mapping, not only upb. At
v36.2: 5389 tests pass and 160 are expected failures, each line of
`failure_list.txt` saying why: 96 for `-2^31` as `NA` (§6.1), 44 for
Timestamp and Duration as microsecond doubles (§6.3), 8 for NUL in
strings, 12 that upb's JSON decoder fails for protobuf's Ruby and PHP
too. Text format's 909 tests are skipped (§2). The fuzz targets
(`tools/fuzz/`) are `fuzz_decode` and `fuzz_json` (upb through the
shim) and `fuzz_build` (embedded R: the builder and the encoder), each
with a canary; they found patch 0006, and that an `NA` from an enum
number the enum lacks cannot be re-encoded inside a repeated field
(`enums = "factor"`, as documented), and showed the encoder's Timestamp
range was the JSON mapping's, not the binary format's (§7, revised). The
conformance run also found that NaN was refused on encode and that `NULL`
in a `Value` field was read as unset; both are fixed. In CI, `fuzz_build`
found a heap use-after-free in zuproto's own batch decoder: the error
path for a message past the memory ceiling read the allocator after
freeing it. Fixed, with a test that takes that path.

## 16. Performance targets

Measured by `tools/run-benchmarks` against `RProtoBuf` where it
installs, and recorded in the design.

**Stage 7, 2026-10-25**, the targets below against RProtoBuf 0.4.28 on
the same machine:

- Batch: `proto_decode_df()` on 10^5 five-field messages, 0.15 s, against
  3.84 s for RProtoBuf's `read()`, `as.list()` and `rbind` per message:
  **25x, target met.**
- Single message: **met, after a fix**. First measured, `proto_decode()`
  took 33 us against 9.3 us for RProtoBuf's `read()`. Split, zuproto's C
  side (decode and build the R list) took 6.2 us, less than `read()`,
  which builds no R values (`read()` plus `as.list()`: 17.9 us); the rest
  was the R wrapper, a dozen small argument-checking calls at 1-3 us each.
  The wrappers now skip arguments left at their defaults, check the rest
  inline, and capture the call only on errors: `proto_decode()` 12.9 us,
  `proto_encode()` 10.3 us against 15.9 us for `serialize()`,
  `proto_to_json()` 14.3 us against 10.7 us for `toJSON()` (5-field
  message, 2026-10-25; this machine's timings vary by about 20%).
- Pool loading: a 0.9 MB descriptor set (2600 types) loads in 29-32 ms in
  a fresh session: **met**. (Measured after 10^6 rows were held in R, it
  took 150 ms, all of it R's garbage collector; the benchmark now
  measures it first.)

**Stage 5, 2026-10-25** (Intel i5-8500B, macOS, R 4.5.2, upb v36.2;
10^6 messages of five scalar fields): `proto_read_delimited()` decodes
them into a data frame in 0.32 s; `proto_decode_df()` on 10^5 raw
vectors takes 0.07 s, 77 times faster than `proto_decode()` per message
plus `rbind` (5.49 s). RProtoBuf was not installed, so the 10x target
below is not yet measured. Encoding is the slow side: 51 s for
`proto_write_delimited()` of 10^6 rows, which builds each row's list in
R; no target covers it, and it is recorded for Stage 7.

Targets:

- `proto_decode_df()` on 10^6 small messages (5 scalar fields): at least
  10× faster than `RProtoBuf` reading the same messages and converting
  them to a data frame.
- Single-message `proto_decode()` and `proto_encode()`: within 2× of
  `RProtoBuf`'s `read()` and `serialize()`.
- Pool loading of a 1 MB descriptor set: under 50 ms.

## 17. Decisions

| # | Question | Decision |
| --- | --- | --- |
| D1 | Runtime | upb, vendored; not C++ protobuf, not protobuf-c |
| D2 | What to vendor | the Ruby amalgamation plus `utf8_range` |
| D3 | Pinning | a release tag; re-vendor on a cadence (§9.4) |
| D4 | Schema input | `FileDescriptorSet` only in 0.1.0 |
| D5 | Many messages | data frames, built column by column |
| D6 | 64-bit integers | `int64 = "double"` default; `"zuint"` lossless |
| D7 | Enums | factors with the definition's names |
| D8 | Descriptors | trusted input; messages untrusted |
| D9 | upb API access | through one shim header only |
| D10 | Text format | none in 0.1.0 |
| D11 | Info function | `zuproto_info()`, the package name (R1) |

Reasons where they are not in the section cited:

- D1: `protobuf-c` needs generated C per schema and has no runtime
  loading of descriptor sets; `nanopb` is code-generated and aimed at
  microcontrollers; the C++ library brings Abseil. upb is the only C
  runtime with reflection over descriptors loaded at run time.
- D2: the Ruby and PHP amalgamations are checked into the protobuf
  repository and need no Bazel to produce, so vendoring is a copy. The
  generic `gen_amalgamation` target has text format but no JSON, and is
  not checked in. Between Ruby's and PHP's, either serves; Ruby's is
  chosen because its build (`extconf.rb`) shows the exact file set,
  including `utf8_range`.
- D4: upb cannot parse `.proto` text (its README), and calling `protoc`
  from a package would add a system requirement for the common case.
  Descriptor sets are what `buf` and `protoc` already produce for
  tooling, and what gRPC reflection serves.
- D6: the family's default for integers beyond 2^53 is a double with a
  warning; zuint is the exact path and the reason it exists (RFC 0009).

## 18. Open questions

1. **The name.** `zuproto` or `zupb`? `zupb` names the runtime,
   `zuproto` the format; the family names formats (`zucbor`,
   `zumsgpack`). Recommended: `zuproto`, after a CRAN, r-universe and
   PyPI check. **Decided 2026-10-24: `zuproto`.** Neither name is on
   CRAN (current or archived), r-universe or PyPI.
2. **`defaults = TRUE`.** Proto3 cannot tell an unset scalar from its
   zero value without presence; returning defaults matches every other
   runtime, returning `NULL` matches the wire. Recommended: defaults, as
   proposed, with `NULL` only for fields with presence. **Decided
   2026-10-25 as recommended.** Proto2 `optional` fields have presence,
   so their declared defaults do not appear when unset.
3. **`proto_compile()`.** Worth adding in 0.1.0 as an optional helper
   that shells out to `protoc` or `buf` when found, or leave it to the
   user? Recommended: leave it to 0.2.0; document the one-line `protoc`
   command instead.
4. **Ruby or PHP amalgamation.** Both carry JSON and reflection;
   measure both in Stage 0 for size and warnings, keep the smaller
   clean one.
5. **Unknown fields.** Keeping them as a raw attribute round-trips them,
   but attributes are easy to lose in R. Is a `proto_message` class
   worth it? Recommended: no class in 0.1.0; plain lists stay plain.
   **Decided 2026-10-25 as recommended.**
6. **A repeated field as a data frame.** A GTFS-RT feed (§22) is one
   `FeedMessage` whose `entity` field repeats, not a stream of messages.
   `proto_decode_df()` takes many messages; decoding one and then
   rebinding `entity` builds the per-object lists that §6.4 avoids.
   Should there be a way to decode a repeated message field straight to a
   data frame, for example `proto_decode_df(raw, "transit_realtime.FeedMessage",
   pool, field = "entity")`? **Decided 2026-10-25: yes, `field =` on
   `proto_decode_df()`** (§6.4).
7. **Extensions.** `gtfs-realtime.proto` is proto2 and reserves extension
   ranges, and agencies publish extensions there. §2 and §6 say nothing
   about extensions, either in the pool (adding extension files) or in
   decoding (how an extension field appears in the list and in the data
   frame). **Decided 2026-10-25:** decoded under bracketed full names
   (§8). It still needs checking whether the Swiss feed's
   `original_trip_id` is an extension or a field.

## 19. Roadmap

| Stage | Title | Size |
| --- | --- | --- |
| 0 | Identity; vendor upb at a tag; measure build, size and NOTEs | M |
| 1 | The shim; pools from descriptor sets; well-known types | M |
| 2 | `proto_decode()`: one message to a list, every field kind | M |
| 3 | `proto_encode()`: lists to bytes, deterministic | M |
| 4 | `proto_decode_df()` and delimited streams | L |
| 5 | Protobuf JSON; `Any`; the int64 options with zuint | M |
| 6 | Conformance suite, fuzzing, hostile inputs, benchmarks | M |
| 7 | Documentation and release 0.1.0 | S |

Stage 0 is a go/no-go: if the amalgamation cannot be made CRAN-clean
with the two patches of §9.2, the RFC returns to the maintainer before
Stage 1.

## 20. Acceptance criteria for v0.1.0

1. Builds everywhere from the package sources alone: no system
   protobuf, no `protoc`, no Abseil.
2. `R CMD check --as-cran` clean on every CI leg; `R_init_zuproto` the
   only export; no stdio, `abort` or `exit` symbols.
3. No R object is built from a message upb did not decode successfully;
   verified by the hostile-input fixtures.
4. Every oversized, deep, truncated or malformed input fails through a
   classed `zuproto_error`; the fuzz gate has been seen to fail on its
   canary.
5. Every fixture round-trips; the conformance suite's expected-failure
   list is recorded and justified line by line.
6. `proto_decode_df()` agrees with `proto_decode()` on every fixture and
   meets §16's batch target.
7. Every mapping row of §6 has a test.
8. `tools/verify-vendor` passes (the vendored files are upstream's at
   the pinned commit plus exactly `tools/patches/`), and no upb symbol
   is used outside the shim.

## 21. What this RFC does not decide

- A `.proto` parser. It would remove the one external step left, and
  the maintainer has turned Ragel and Lemon into R-callable C before,
  but it is a compiler front end with imports, options and editions,
  and deserves its own RFC.
- gRPC. A client would sit on `zuhttp` and this package; it is a
  separate package if ever.
- Whether zuproto should replace `RProtoBuf` for its users. The case is
  §3's gap: no system library, columns for many messages. The
  maintainer judges the audience.

## 22. Worked example: Swiss GTFS-RT

Added 2026-10-24. The README and the main vignette use GTFS Realtime, the
protobuf feed format transit agencies use for live data, with a Swiss
source. It suits the package for three reasons: the schema is a real proto2
`.proto` with nested and repeated messages, enums and optional fields; the
payloads are binary protobuf with no other format on offer; and the result
people want is a table of trips and delays.

**The source.** opentransportdata.swiss, as checked on 2026-10-24:

- Trip Updates at `https://api.opentransportdata.swiss/la/gtfs-rt`, as
  binary protobuf (`?format=JSON` exists for testing). Service Alerts is a
  separate feed (GTFS-SA). There is no Vehicle Positions feed, so the
  example covers trip updates and alerts only.
- An API key from the platform's API Manager, sent as
  `Authorization: Bearer <key>`. Requests must set `User-Agent` and
  follow redirects. The limit is 2 requests per minute per key. The data
  is refreshed every 30 seconds.
- Swiss profile specifics: stop IDs in SLOID form (`ch:1:sloid:…`),
  `original_trip_id` for VDV454 trip IDs, and `FeedVersion` in the header
  naming the matching GTFS static release.

transport.opendata.ch ("Transport API") returns JSON built from the same
data, not protobuf, so it is not a zuproto source. The vignette can
mention it as the JSON alternative.

**Nothing ships for it** (decided 2026-10-24). No descriptor set, feed
snapshot or fixture from this example goes into the package; it lives only
in the documentation. The reader compiles MobilityData's
`gtfs-realtime.proto` with `protoc --descriptor_set_out` and fetches the
feed with their own key.

**Where it goes.** In the README if a good example fits in 7 lines of
code, and never more than 10, counting the `protoc` line; otherwise in a
vignette, with the README pointing to it. The chunks are not evaluated,
because CRAN builds have no key, no `protoc` and no network guarantee.
Output shown under them is pasted from a real run, dated.

**What it demonstrates:** loading a pool from a descriptor set; decoding
one `FeedMessage` to a list; trip updates as a data frame (trip ID, route,
stop, delay), which needs §18 question 6 settled first; enums as factors
(`ScheduleRelationship`, alert `Effect`); `POSIXct` from the header's
POSIX `timestamp`, which is a `uint64` here and not a well-known
`Timestamp`; and `proto_to_json()` against the feed's JSON form.

Review prepared with assistance from generative AI.
