# Stage 3 — Decode one message: implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use
> superpowers:executing-plans to implement this plan task-by-task (chosen:
> native, with one fresh whole-branch review before the pull request).

**Goal:** `proto_decode()` turns one message into a named list for every
field kind design §6.1–§6.3 maps.

**Architecture:** `src/zpb_decode.c` decodes into an arena owned by a
finalised external pointer (with a counting allocator for the arena
ceiling), and only after `kUpb_DecodeStatus_Ok` does `src/zpb_build.c`
walk the message by reflection into R values. Build functions return
`NULL` with an error recorded in a context and their PROTECTs balanced;
the entry point returns `list(value, error, warnings)` and `R/decode.R`
raises or warns with the classed conditions.

**Tech Stack:** C99, base R; fixtures from Python `protobuf==7.36.2`
(upb-backed, matching the vendored v36.2).

**Spec:** roadmap § Stage 3; design §4, §5, §6.1–§6.3, §11, §12, §13.

## Global Constraints

- Decisions of 2026-10-25 (maintainer): `defaults = TRUE` gives unset
  no-presence fields their defaults, presence fields are left out when
  unset; plain lists, unknown fields in attribute `proto_unknown`;
  int32-family `-2^31` is `NA` with `zuproto_precision_loss`; a NUL in a
  string is `zuproto_unrepresentable`; maps sorted by key; extensions
  under `[full.name]`.
- `int64 =` accepts `"double"` and `"character"` only until Stage 6.
- No R API call while upb is decoding; no R object built from a message
  that did not decode.
- Required fields are not checked on decode (upb's default; proto2
  `required` missing decodes as unset). Encoding checks them (Stage 4).

## Review Focus

- A 2^31-byte length prefix with three bytes after it: `zuproto_parse_error`,
  no allocation of 2 GB.
- Nesting one deeper than `max_depth`: `zuproto_depth_limit`.
- A packed repeated field that expands past the arena ceiling:
  `zuproto_size_limit`, not an out-of-memory crash.
- An enum value outside an open enum: `NA` plus `zuproto_unknown_enum`
  (factor) or the number (integer).
- `int64` beyond 2^53 under `"double"`: value rounded plus
  `zuproto_precision_loss`, one warning per call.

---

### Task 1: Fixtures

- `tests/testthat/fixtures/proto/decode.proto` (proto3) and
  `decode2.proto` (proto2: closed enum, defaults, extension, unpacked
  repeated, group-free) covering every §6 row and every well-known type.
- `tools/make-fixtures.py`: reads the fixture descriptor sets, builds
  messages from dicts with `json_format.ParseDict`, writes
  `fixtures/msg/<name>.binpb` and `fixtures/msg/MANIFEST.tsv` (name, type,
  source, SHA-256).

### Task 2: Decoder and builder (C)

- Shim: decode, arena with allocator, reflection getters, enum lookups,
  unknown-field iteration, well-known-type detection.
- `zpb_decode(pool, type, raw, opts)` → `list(value, error, warnings)`.

### Task 3: R interface

- `proto_decode(x, type, pool, int64, enums, defaults, unknown, bytes,
  max_size, max_depth)`; argument checks; input reading capped at
  `max_size + 1`; conditions `zuproto_parse_error`, `zuproto_invalid_utf8`,
  `zuproto_unrepresentable`, `zuproto_limit_error` /
  `zuproto_depth_limit` / `zuproto_size_limit`; warnings
  `zuproto_unknown_enum`, `zuproto_precision_loss`.

### Task 4: Tests

- One test per §6.1–§6.3 row against the fixtures; every argument; the
  Review Focus inputs; hostile inputs built from bytes in the test.

### Task 5: Verify and review

- `devtools::check()`, shuffle, CRAN-like `-pedantic` check,
  `tools/verify-vendor`; fresh reviewer over the branch; full CI profile.
