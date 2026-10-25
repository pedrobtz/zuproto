# zuproto: roadmap

Status: draft 2026-10-24, revised 2026-10-24 in Stage 0 (`Suggests`
moved to the stages that use them). Implements [design.md](design.md).
Target: v0.1.0, the first CRAN release.
Tracking: [v0.1.0 (#1)](https://github.com/pedrobtz/zuproto/issues/1), with
one sub-issue per stage;
[CRAN-submission (#13)](https://github.com/pedrobtz/zuproto/issues/13).

The design's own roadmap (§19) has eight stages. Here its Stage 0 is split
into package identity and the vendoring spike, its Stage 7 into
documentation and release, and `Full CI` goes in before the release.

## Stages

| Stage | Title | CI | Issue | Pull request | Done |
| --- | --- | --- | --- | --- | --- |
| 0 | [Package identity](#stage-0--package-identity) | quick | [#2](https://github.com/pedrobtz/zuproto/issues/2) | [#14](https://github.com/pedrobtz/zuproto/pull/14) | 2026-10-24 |
| 1 | [Vendor upb](#stage-1--vendor-upb) | full | [#3](https://github.com/pedrobtz/zuproto/issues/3) | [#15](https://github.com/pedrobtz/zuproto/pull/15) | 2026-10-25 |
| 2 | [Shim, pools and well-known types](#stage-2--shim-pools-and-well-known-types) | quick | [#4](https://github.com/pedrobtz/zuproto/issues/4) | [#16](https://github.com/pedrobtz/zuproto/pull/16) | 2026-10-25 |
| 3 | [Decode one message](#stage-3--decode-one-message) | full | [#5](https://github.com/pedrobtz/zuproto/issues/5) | [#17](https://github.com/pedrobtz/zuproto/pull/17) | 2026-10-25 |
| 4 | [Encode one message](#stage-4--encode-one-message) | quick | [#6](https://github.com/pedrobtz/zuproto/issues/6) | [#18](https://github.com/pedrobtz/zuproto/pull/18) | 2026-10-25 |
| 5 | [Data frames and delimited streams](#stage-5--data-frames-and-delimited-streams) | quick | [#7](https://github.com/pedrobtz/zuproto/issues/7) | | 2026-10-25 |
| 6 | [JSON, Any and 64-bit integers](#stage-6--json-any-and-64-bit-integers) | quick | [#8](https://github.com/pedrobtz/zuproto/issues/8) | | |
| 7 | [Conformance, fuzzing and hostile inputs](#stage-7--conformance-fuzzing-and-hostile-inputs) | quick | [#9](https://github.com/pedrobtz/zuproto/issues/9) | | |
| 8 | [Documentation](#stage-8--documentation) | quick | [#10](https://github.com/pedrobtz/zuproto/issues/10) | | |
| 9 | [Full CI](#stage-9--full-ci) | full | [#11](https://github.com/pedrobtz/zuproto/issues/11) | | |
| 10 | [v0.1.0 readiness](#stage-10--v010-readiness) | full | [#12](https://github.com/pedrobtz/zuproto/issues/12) | | |

## Stage 0 — Package identity

**Issue.** [#2](https://github.com/pedrobtz/zuproto/issues/2), sub-issue of
[v0.1.0](https://github.com/pedrobtz/zuproto/issues/1).

**CI.** `quick`. See the CI policy in `CLAUDE.md`.

**Goal.** The package has its real identity and CI, and nothing else.

**Work.**

- `DESCRIPTION`: real Title and Description, `Authors@R` with `cre`, `aut`,
  `cph`, `Depends: R (>= 4.1)`, `Language: en-GB`,
  `Suggests: testthat (>= 3.0.0)`, no `Imports` or `LinkingTo`,
  `BugReports`. *Deviation, 2026-10-24:* bit64 and zuint move to Stage 6
  and withr to the first stage whose tests use it. zuint is at 0.0.0.9000
  on neither CRAN nor r-universe, so suggesting it now is a NOTE and a
  failed dependency install in CI.
- Settle the name (open question 1): CRAN, r-universe and PyPI checked, and
  the result recorded in the design.
- Check the `zpb_` / `ZPB_` prefix against every sibling's source and record
  the result in the design (§3).
- `R-CMD-check` caller: add the `{"os": "windows-latest", "r": "devel"}`
  runner row.
- `coverage.yaml`: pin `coverage.yml` to a commit with the tag in a comment,
  as `CLAUDE.md` requires for a workflow holding a write token.
- `.Rbuildignore` and `CLAUDE.md` (done by `pkg-init`): keep in step.
- Replace the placeholder test with a test of package loading.

**Exit criteria.**

- `DESCRIPTION` has no scaffold placeholders; `R CMD check` passes on the
  quick r-actions profile, including the Windows R-devel leg.
- Every quick-profile check on the stage's pull request finishes in under
  five minutes, or the tuning that got it there is recorded here.
- The design records the name check and the prefix check.

**Design.** §3, §14 (`DESCRIPTION`), §18 question 1.

## Stage 1 — Vendor upb

**Issue.** [#3](https://github.com/pedrobtz/zuproto/issues/3), sub-issue of
[v0.1.0](https://github.com/pedrobtz/zuproto/issues/1).

**CI.** `full — first compiled code and a vendored library: sanitizers,
valgrind, rchk and every platform leg must see the amalgamation before
anything is built on it.`

**Goal.** upb and `utf8_range` compile into the package at a pinned
release, CRAN-clean, with only the design's two patches. This is the
go/no-go: if that fails, the design goes back to the maintainer before
Stage 2.

**Work.**

- Measure the Ruby and PHP amalgamations for size and warnings, keep the
  smaller clean one (open question 4), and record why.
- `tools/vendor-upb <tag>`: fetch a protobuf release tag (`v36.2` or
  later), copy the amalgamation to `src/upb/upb.{c,h}` and `utf8_range`,
  apply `tools/patches/`, write `src/upb/VERSION` (tag, commit, SHA-256 per
  file).
- `tools/patches/`: `UPB_ASSERT` as a no-op; the `fprintf(stderr, …)` and
  `abort()` sites routed to a flag. Each patch with its reason.
- Upstream licences in `src/upb/` and `inst/COPYRIGHTS`; `DESCRIPTION`
  declares the vendored code.
- `src/Makevars` and `src/Makevars.win`: `PKG_CFLAGS = $(C_VISIBILITY)`,
  the amalgamation and `utf8_range` built in, `R_init_zuproto` the only
  export.
- A CI step running `nm -u` on the built objects, failing on stdio,
  `abort`, `exit` and system RNG symbols.
- A test that `src/upb/VERSION` matches the vendored files' hashes.
- Record in the design: compile time and shared-object size per CI leg,
  warnings under CRAN's gcc and clang flags and which were silenced, the
  C standard the amalgamation needs, the tarball size.

**Exit criteria.**

- A full-profile r-actions run is green on the pull request.
- `R CMD check` shows no compiled-code NOTE; the `nm -u` step passes.
- The vendored files match `src/upb/VERSION`, and the patch list has no
  entry beyond the two the design allows.
- The measurements are recorded in the design, with the go decision.

**Deviations, 2026-10-25.** Decided with the maintainer after the
unpatched full CI run on #15:

- Four patches plus one define, not two patches (design §9.2, revised;
  Stage 3 added a fifth).
  The `UPB_ASSERT` patch is not needed, since `R CMD INSTALL` defines
  `NDEBUG`.
- Layout `src/vendor/{upb,utf8_range}/` with `src/vendor/PROVENANCE`, as
  zuhtml does and r-actions' `vendor.yml` expects, instead of `src/upb/`
  with `src/upb/VERSION`. The hash check is `tools/verify-vendor`, run by
  the `vendor` workflow, instead of a testthat test, since the installed
  package has no `src/`.
- The `nm -u` guard is `tests/testthat/test-symbols.R`, which runs on
  every CI leg that has `nm`, instead of a separate CI step.
- Ruby amalgamation kept (open question 4); the reason is in design §9.1.

**Design.** §9.1, §9.2, §14; §18 question 4.

## Stage 2 — Shim, pools and well-known types

**Issue.** [#4](https://github.com/pedrobtz/zuproto/issues/4), sub-issue of
[v0.1.0](https://github.com/pedrobtz/zuproto/issues/1).

**CI.** `quick`. The pools' external pointers and finalizers are exercised
by Stage 3's full run, which builds on them.

**Goal.** Descriptor sets load into pools that R can list, through the one
header that touches upb.

**Work.**

- `src/zpb_upb.h`: the shim's `static inline` wrappers for the operations
  §9.3 lists, and a test that no upb symbol is used outside it.
- Condition helpers for `zuproto_error` and its subclasses (§11).
- `proto_pool()`, `proto_pool_add()` (raw, path, connection), with
  dependency order, missing imports by file name, identical files skipped
  and `zuproto_pool_conflict` on different bytes.
- `proto_types()` and `proto_fields()` as data frames.
- `inst/descriptors/wkt.binpb` generated by `tools/vendor-upb`, checked by
  SHA-256 in tests.
- `zuproto_info()`.
- Decide how extensions load (open question 7), and test that an editions
  descriptor loads.

**Exit criteria.**

- Pools load every well-known type and a test schema's descriptor set;
  missing imports and conflicts fail with their condition classes.
- The shim audit test passes.
- `R CMD check` passes on the quick r-actions profile.

**Deviations, 2026-10-25.**

- `wkt.binpb` is checked by its SHA-256 in `src/vendor/PROVENANCE`,
  through `tools/verify-vendor`, not by a test: base R before 4.5 has no
  SHA-256, and the package supports R 4.1. The shim audit is in
  `tools/verify-vendor` too, since the installed package has no `src/`.
- Extensions decided with the maintainer (open question 7): design §8.
- withr joins `Suggests` here, its first use in tests.

**Design.** §8, §9.3, §11; §18 question 7.

## Stage 3 — Decode one message

**Issue.** [#5](https://github.com/pedrobtz/zuproto/issues/5), sub-issue of
[v0.1.0](https://github.com/pedrobtz/zuproto/issues/1).

**CI.** `full — the first decoder of untrusted input and the first R
values built from upb memory (PROTECT, arena external pointers): gctorture,
valgrind and ASan.`

**Goal.** `proto_decode()` turns one message into a named list for every
field kind the design maps.

**Work.**

- `tools/make-fixtures.py` with a pinned Python `protobuf`, and
  `protoc --encode`, for a test schema covering every field kind,
  presence, maps, oneofs, packed and unpacked repeated fields, editions and
  every well-known type; a manifest with each file's source and SHA-256.
- `src/zpb_decode.c` and `src/zpb_build.c`: decode into a per-call arena
  held by an external pointer, build only after `kUpb_DecodeStatus_Ok`.
- The mappings of §6.1–§6.3, the decode arguments of §5 (`int64` limited to
  `"double"` and `"character"` until Stage 6), `max_size`, `max_depth`, the
  arena byte ceiling, UTF-8 validation for every `string` field.
- `unknown = "keep"` as the `proto_unknown` attribute.
- Settle open questions 2 (`defaults`) and 5 (a message class) before
  writing the build code; extension fields as decided in Stage 2.

**Exit criteria.**

- A full-profile r-actions run is green on the pull request.
- Every mapping row of §6.1–§6.3 has a test against a generated fixture.
- Malformed, oversized and too-deep inputs fail with their
  `zuproto_error` subclasses, and no R object is built for them.

**Deviations, 2026-10-25.**

- Decided with the maintainer before the build code: questions 2 and 5
  as recommended; `-2^31` as `NA` with a warning; NUL in a string as the
  new `zuproto_unrepresentable`; maps sorted by key (design §6).
- Fixtures come from Python `protobuf` 7.36.2 alone, not also
  `protoc --encode`: one independent encoder is enough for decoding, and
  `protoc --encode` joins in Stage 4's round trips if needed. Message
  fixtures are stored as hex text (`fixtures/msg/*.hex`), because
  `R CMD check` took three short binary ones for executables.
- Required fields are not checked on decode, as upb does by default.
- `zuproto_invalid_utf8` is a subclass of `zuproto_parse_error`.
- A fifth vendoring patch, `0005-flexible-str.patch` (design §9.2), for
  UBSan's report on upb's `char str[1]` struct hack, found by this
  stage's full run.
- `max_depth` is at most 1000 (design §12): the fresh review found that
  upb's recursive decoder exhausts the C stack at about 5000 levels.
- Left for Stage 7's conformance suite, from the review: enum aliases,
  message-typed and repeated-message extensions, and Timestamp
  rounding ties.

**Design.** §4, §5, §6.1–§6.3, §12, §13; §18 questions 2 and 5.

## Stage 4 — Encode one message

**Issue.** [#6](https://github.com/pedrobtz/zuproto/issues/6), sub-issue of
[v0.1.0](https://github.com/pedrobtz/zuproto/issues/1).

**CI.** `quick`.

**Goal.** `proto_encode()` turns a named list back into deterministic
bytes.

**Work.**

- `src/zpb_fill.c`: walk the message definition, type-check each field,
  `zuproto_unknown_field` (or `extra = "ignore"`), whole and in-range
  doubles for integer kinds, `NA` as unset.
- `deterministic`, `unknown` and `check_required` arguments.
- The encoded bytes copied into a raw vector before the arena is freed.

**Exit criteria.**

- Decode → encode → decode is identical for every fixture; encode → decode
  is identical for generated values of every §6 mapping row.
- Type mismatches and missing required fields fail with their condition
  classes.
- `R CMD check` passes on the quick r-actions profile.

**Deviations, 2026-10-25.** The cases §7 left open are decided in
design §7 (duplicate map keys, oneofs, `NA` in repeated fields,
Timestamp and Duration ranges, raw-only `bytes`). The strongest test is
byte identity: re-encoding each Python fixture gives Python's
deterministic bytes.

**Design.** §5 (encode arguments), §7, §13.

## Stage 5 — Data frames and delimited streams

**Issue.** [#7](https://github.com/pedrobtz/zuproto/issues/7), sub-issue of
[v0.1.0](https://github.com/pedrobtz/zuproto/issues/1).

**CI.** `quick`. The C build code it adds is covered by `Full CI`.

**Goal.** Many messages decode into a data frame built column by column,
and delimited streams read and write.

**Work.**

- `proto_decode_df()`: every message into one arena, then one pass per
  column, as §6.4 describes; the column shapes of §6.2; `max_rows`.
- Decoding a repeated message field of one message to a data frame, as
  settled in open question 6 (the GTFS-RT `FeedMessage.entity` case).
- `proto_read_delimited()` with `each` and `chunk_rows`;
  `proto_write_delimited()` from a data frame or list.
- Interrupt checks between messages and every 65,536 rows.
- A first benchmark in `tools/run-benchmarks` against the §16 batch
  target.

**Exit criteria.**

- `proto_decode_df()` equals `proto_decode()` row by row for every fixture.
- A delimited stream ending inside a varint fails with a classed error.
- `R CMD check` passes on the quick r-actions profile.

**Deviations, 2026-10-25.** Question 6 decided with the maintainer:
`field =` on `proto_decode_df()`; the column decisions it led to are in
design §6.4. `proto_write_delimited()` converts rows to messages in R,
which is slow (51 s for 10^6 rows, design §16); a C path for it is left
for Stage 7, which owns the benchmarks.

**Design.** §6.2, §6.4, §10, §12; §18 question 6.

## Stage 6 — JSON, Any and 64-bit integers

**Issue.** [#8](https://github.com/pedrobtz/zuproto/issues/8), sub-issue of
[v0.1.0](https://github.com/pedrobtz/zuproto/issues/1).

**CI.** `quick`. The new `Suggests` guards get their `nosuggests` run in
`Full CI`.

**Goal.** Protobuf JSON works both ways, `Any` unpacks, and 64-bit fields
have their lossless options.

**Work.**

- `proto_to_json()` and `proto_from_json()` through upb's JSON;
  `zuproto_json_error`.
- `proto_unpack_any()`.
- `int64 = "zuint"` and `"integer64"`, each guarded by
  `requireNamespace()`, and the `zuproto_precision_loss` warning under
  `"double"`. bit64 and zuint join `Suggests` here (moved from Stage 0).

**Exit criteria.**

- JSON round-trips every fixture; `Any` unpacks against the pool.
- 64-bit fixtures beyond 2^53 are exact under `"zuint"` and `"character"`
  and warn under `"double"`; tests skip cleanly without zuint or bit64.
- `R CMD check` passes on the quick r-actions profile.

**Design.** §5, §6.1, §6.3 (`Any`), §3 (relationships).

## Stage 7 — Conformance, fuzzing and hostile inputs

**Issue.** [#9](https://github.com/pedrobtz/zuproto/issues/9), sub-issue of
[v0.1.0](https://github.com/pedrobtz/zuproto/issues/1).

**CI.** `quick` for the package check; the conformance and fuzz jobs are
their own CI jobs.

**Goal.** The package is tested against protobuf's own suite, a fuzzer and
every hostile input the design names.

**Work.**

- An R testee for `conformance_test_runner`, run for the binary and JSON
  suites in a CI job, with a justified expected-failure list.
- A `zufuzz` decode target over a fixed pool, under ASan and UBSan, seeded
  from every fixture, with a canary.
- The hostile inputs of §15 as permanent regression tests.
- `tools/run-benchmarks` against `RProtoBuf` where it installs, results
  recorded in the design.

**Exit criteria.**

- The conformance job is green against its expected-failure list, and each
  entry has a reason.
- The fuzz job has been seen to fail on its canary and passes without it.
- Every hostile input of §15 has a test that passes.
- §16's targets are measured and recorded, met or not.

**Design.** §15, §16.

## Stage 8 — Documentation

**Issue.** [#10](https://github.com/pedrobtz/zuproto/issues/10), sub-issue of
[v0.1.0](https://github.com/pedrobtz/zuproto/issues/1).

**CI.** `quick`.

**Goal.** The README sells the package with the Swiss GTFS-RT example (or
points to a vignette holding it), and every export is documented.

**Work.**

- The GTFS-RT example as §22 describes: in `README.Rmd` if it fits in 7
  lines (10 at most), otherwise in a vignette. Not evaluated; output pasted
  from a dated live run. Nothing from it ships in the package.
- An evaluated README chunk on a schema the package already has (the
  well-known types), so the README still shows real output.
- roxygen for every export, the trusted-descriptors note, and a pkgdown
  reference index.

**Exit criteria.**

- No file under `inst/` comes from the GTFS-RT example.
- The example's code is at most 10 lines if it is in the README.
- `R CMD check` passes on the quick r-actions profile with no
  documentation warnings.

**Design.** §22; §8 (trusted input).

## Stage 9 — Full CI

**Issue.** [#11](https://github.com/pedrobtz/zuproto/issues/11), sub-issue of
[v0.1.0](https://github.com/pedrobtz/zuproto/issues/1).

**CI.** `full`.

**Goal.** The full r-actions profile is green on the default branch's code.
No new features.

**Work.**

- Run the full profile (`full-ci` label): gctorture at the sensitive step,
  valgrind, ASan, every platform leg, `nosuggests`, `nold`, cran-special.
- Fix everything it finds, and everything recorded on this issue from
  earlier merges.

**Exit criteria.**

- A full-profile run is green on the pull request and on its merge commit.

**Design.** §14, §20 (criteria 1 and 2).

## Stage 10 — v0.1.0 readiness

**Issue.** [#12](https://github.com/pedrobtz/zuproto/issues/12), sub-issue of
[v0.1.0](https://github.com/pedrobtz/zuproto/issues/1).

**CI.** `full`.

**Goal.** Only the submission itself is left.

**Work.**

- `Version: 0.1.0` and the matching `NEWS.md` heading.
- `cran-comments.md` listing the r-actions CI legs as test environments.
- `pkg-critical-review`, with its blocking and required findings fixed.
- `pkg-cran-review`, with every finding resolved.
- `urlchecker::url_check()` and `spelling::spell_check_package()` clean.

**Exit criteria.**

- Every acceptance criterion of §20 holds.
- A full-profile r-actions run is green on the release commit.

**Design.** §20.

## After 0.1.0

- `proto_compile()` calling `protoc` or `buf` from `PATH`: a system
  requirement for an optional helper; document the `protoc` command instead
  (§18 question 3, recommended for 0.2.0).
- A native `.proto` parser: a separate RFC (§21).
- gRPC server reflection as a descriptor source, and gRPC's 5-byte framing.
- Text-format output for debugging.
- Parallel decoding into upb arenas.

## Open questions

- **zuint not on CRAN**: blocks Stage 6's `"zuint"` option. zuint must
  reach CRAN (or at least r-universe, with `Additional_repositories`)
  before zuproto can suggest it; otherwise `int64 = "zuint"` waits for
  0.2.0.
