# Stage 4 — Encode one message: implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use
> superpowers:executing-plans to implement this plan task-by-task.

**Goal:** `proto_encode()` turns a named list back into deterministic
bytes.

**Architecture:** `src/zpb_fill.c` walks the R value against the message
definition and sets fields on a upb message in an arena owned by a
finalised external pointer; a type error stops the walk with an error
code and the field's path (`points[2].x`), and R raises it. upb then
encodes deterministically into the same arena, and the bytes are copied
into a raw vector before the arena is freed. Strings handed to upb point
into R memory that lives until the `.Call` returns.

**Spec:** roadmap § Stage 4; design §5 (encode arguments), §7, §13.

## Global Constraints

- The inverse of every decode mapping (design §6), so decode → encode →
  decode is the identity on every fixture, and re-encoding a fixture
  gives Python's deterministic bytes.
- Names the type does not define: `zuproto_unknown_field` (path), or
  skipped with `extra = "ignore"`. `[pkg.ext]` names an extension.
- Integer kinds take integers or whole doubles in range; 64-bit kinds
  also decimal strings, exactly. `NA` and `NULL` mean unset.
- Wrong R types, out-of-range or non-whole numbers, unknown enum names,
  two members of one oneof, and `NA` inside a repeated field:
  `zuproto_type_mismatch` with `path`.
- `check_required = TRUE`: a missing proto2 `required` field is
  `zuproto_missing_required`. `unknown = TRUE` writes a `proto_unknown`
  attribute back.
- `bytes` fields take raw vectors only in 0.1.0.

## Review Focus

- `-2^31` as an R `NA_integer_` cannot reach an int32 field: it is unset.
- A factor whose level is not in the enum, or an enum number a closed
  enum lacks: type mismatch, not a silently wrong number.
- A POSIXct before 1970 with a fraction: seconds and nanos keep
  protobuf's sign rule (nanos non-negative for Timestamp).
- A map with `NA` or duplicate names, or an integer-keyed map whose
  name is not a decimal integer in range.
- Deeply nested R lists: `R_CheckStack()`, not a crash.

---

1. Shim: message creation, set/mutable/append/map-set, add-unknown,
   extension and enum lookups, encode with options.
2. `src/zpb_fill.c` and `zpb_encode()`; registration.
3. `R/encode.R`: `proto_encode(x, type, pool, deterministic = TRUE,
   unknown = TRUE, check_required = TRUE, extra = c("error", "ignore"))`.
4. Tests: fixture bytes reproduced; decode → encode → decode for every
   fixture; every §6 row from R values; every error class with its
   path; Review Focus cases.
5. Local loop, CRAN-like check, `tools/verify-vendor`; quick CI.
