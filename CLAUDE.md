# CLAUDE.md

<!-- markdownlint-disable-next-line MD013 -->
This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Shared conventions

The portfolio's shared rules are synced into `.claude/shared/` from
`pedrobtz/packages:claude/shared/`. Never edit them here. Where this file and
a shared file disagree, this file wins for this package.

@.claude/shared/workflow.md
@.claude/shared/r-package.md
@.claude/shared/ci.md
@.claude/shared/native-code.md
@.claude/shared/correctness.md
@.claude/shared/assurance.md

## What this is

zuproto decodes and encodes Protocol Buffers messages in R through upb, the
small C runtime under protobuf's Python, Ruby and PHP implementations. It works
from descriptor sets (`protoc --descriptor_set_out`, `buf build`), not
generated code: one message becomes a named list, many messages become a data
frame built column by column. It also converts to and from protobuf's
canonical JSON, and packs and unpacks `Any`. It is a format package in the
`zu*` family, like zucbor and zumsgpack, except that every call names a
message type in a descriptor pool. upb and `utf8_range` are vendored, so there
is no system protobuf, `protoc` or Abseil. Hard runtime dependencies are zero:
no `Imports`, no `LinkingTo`; zuint and bit64 are in `Suggests` for 64-bit
fields. It will not generate R code per message type, parse `.proto` or text
format, or speak gRPC.

The specification is [`.agents/design.md`](.agents/design.md), adopted from
[RFC 0010](https://github.com/pedrobtz/packages/blob/main/rfcs/started/0010-zuproto-protocol-buffers.md).
It outranks this file: `CLAUDE.md` orients, the design doc decides. Its open
questions (§18) are still open.

## Current state

Verified 2026-11-11. Every stage of the roadmap in `.agents/roadmap.md` is
merged, and v0.1.0 was submitted to CRAN on 2026-11-06
(`CRAN-SUBMISSION`); it is in the incoming queue. Later work is filed as
`enhancement` issues (a `.proto` compiler, text format, TFRecord framing,
`proto_equal()` and others), plus #128, a upb JSON UTF-8 fix for the next
re-vendor.

## Versions and dependents

The current version's parent issue is
[#1](https://github.com/pedrobtz/zuproto/issues/1) for `v0.1.0`; the
CRAN-submission issue is [#13](https://github.com/pedrobtz/zuproto/issues/13).
Sibling packages that depend on this one before CRAN does: none, and
zuproto has no C API.

## Commands

Run from the package root.

```sh
tools/verify-vendor                              # vendor, wkt.binpb, shim
tools/make-test-descriptors                      # after editing fixtures/proto/
```

`tools/vendor-upb`, `tools/make-test-descriptors` and the fixtures need
`protoc` (`brew install protobuf`).

Occasional, for C changes and before a release:

```sh
tools/run-fuzz 60                                # fuzz targets, ASan + UBSan
CANARY_ONLY=1 tools/run-fuzz                     # every canary must crash
CONFORMANCE_RUNNER=<path> tools/conformance/run  # protobuf conformance suite
R CMD INSTALL . && tools/run-benchmarks          # design section 16
```

The conformance runner is built from protobuf at the vendored tag with CMake
(`-Dprotobuf_BUILD_CONFORMANCE=ON`); `.github/workflows/conformance.yaml`
shows how. The runner matches each expected failure's message, so after a
change that alters how a listed test fails, regenerate the list with
`tools/conformance/update-failure-list.py`. After changing fixtures, run
`Rscript tools/fuzz/make-fuzz-data.R` to refresh the fuzz seeds and
`tools/fuzz/data.h`.

## Architecture

`.agents/design.md` §4 has the whole plan.

- **`src/zpb_upb.h` is the shim**: the only file that includes
  `src/vendor/upb/ruby-upb.h` or names a upb symbol. Everything else uses its
  `zpb_` types and `static inline` wrappers. `tools/verify-vendor` fails on a
  leak.
- **C returns, R raises.** `.Call` entry points (`src/zpb.h`, registered in
  `src/init.c`) return a value or an error string; `R/` turns that into a
  classed condition with `zpb_abort()` (`R/conditions.R`). C calls
  `Rf_error()` only for out-of-memory and broken internal invariants.
- **Pools** (`R/pool.R`, `src/zpb_pool.c`): a list of the external pointer to
  upb's `upb_DefPool` and an environment of the files added, name to bytes.
  R checks a whole set (conflicts, missing imports, dependency order) before
  C adds any file. Every pool starts from `inst/descriptors/wkt.binpb`.
- **Decoding** (`R/decode.R`, `src/zpb_decode.c`, `src/zpb_build.c`): upb
  decodes into an arena on a counting allocator (the `4 * max_size`
  ceiling), held with that allocator by one finalised external pointer.
  Building R values starts only after a successful decode and walks the
  message by reflection. A value R cannot hold sets `ctx->err`, and every
  builder then returns `NULL` with its PROTECTs undone; warnings are counted
  in `ctx` and raised once by R.
- **Encoding** (`R/encode.R`, `src/zpb_fill.c`): the R value is walked
  against the message definition and set on a upb message, then upb encodes.
  A wrong value stops the walk with an error code, a detail and the field's
  path (`ctx->path`), which R raises. Strings handed to upb point into R
  memory, valid until the `.Call` returns.
- **Data frames** (`R/frame.R`, `build_frame()` in `src/zpb_build.c`,
  `zpb_decode_df()` in `src/zpb_decode.c`): all messages are decoded into one
  arena, then each column is filled across all rows. `rows[i]` may be `NULL`
  (a nested message the parent row lacks), which makes that row `NA`.
  Delimited framing is in C; R reads connections in chunks for `each`.
- **JSON and `Any`** (`R/json.R`, design §5 and §6.3): upb converts between
  binary and JSON; R checks arguments and raises. An `Any` converts only
  when the type it packs is in the pool.
- **Message fixtures** come from Python `protobuf` 7.36.2 through
  `tools/make-fixtures.py` (it says how to set up the venv), stored as hex
  in `tests/testthat/fixtures/msg/` with a `MANIFEST.tsv`.
- **Test fixtures** are `protoc` output: edit
  `tests/testthat/fixtures/proto/*.proto`, run `tools/make-test-descriptors`,
  commit the `.binpb` files.

## Invariants that are easy to break

- **All upb calls go through `src/zpb_upb.h`.** No other file includes the
  vendored header, and `tools/verify-vendor` enforces it. Otherwise a
  re-vendor, against upb's unstable API, means edits all over `src/`.
- **Never call R while upb is on the C stack.** upb uses `setjmp`/`longjmp`
  for decoder errors; an R error unwinding through those frames skips its
  cleanup. Build R values only after `upb_Decode` returns
  `kUpb_DecodeStatus_Ok`, and never from a partly decoded message.
- **upb memory is owned by finalised external pointers.** Each decode arena
  is wrapped from the moment it is created, so an interrupt during the R build
  phase frees it. No upb pointer is stored in an R object any other way, and
  strings are copied into `CHARSXP`s, never aliased.
- **Descriptor sets are trusted, message bytes are not.** Every limit
  (`max_size`, `max_depth`, `max_rows`, the arena byte ceiling) and UTF-8
  validation applies to message bytes.
- **Vendored patches are only those in the design (§9.2).** Each one is
  listed there with its reason, and each upb bug it works around is
  reported upstream. A patch that touches decoder logic is a reason to
  stop and report upstream.
- **A builder that fails returns `NULL` with its PROTECTs undone**, never
  `Rf_error()`: the entry point must hand the error back to R to raise with
  its class. Only out-of-memory and broken internal invariants call
  `Rf_error()` directly.
- **Iterators start at `ZPB_*_ITER_BEGIN`, not 0.** upb's begin values are
  `(size_t) -1`; 0 is a valid position.
- **Internal native symbols use `zpb_` / `ZPB_`**, not `zuproto_`. This is a
  deliberate deviation from the package-prefix rule in
  `.claude/shared/r-package.md`. `R_init_zuproto` is the only exported
  symbol (hidden visibility from Stage 0).

## Testing

- **Conformance.** The oracle is protobuf's `conformance_test_runner`, run
  against an R testee (`tools/conformance/`) through the binary and JSON
  suites, in CI only. Its expected-failure lists
  (`tools/conformance/failure_list.txt`, `text_format_failure_list.txt`) may
  only shrink: the run fails on a test that fails outside the list, or on a
  listed one that passes.
- **Fixtures** come from Python's `protobuf` and `protoc --encode`, never by
  hand. They are written by `tools/make-test-descriptors` (protoc) and
  `tools/make-fixtures.py` (Python's protobuf), with provenance and SHA-256
  in `fixtures/DESCRIPTORS.tsv` and `fixtures/msg/MANIFEST.tsv`.
- **Helpers.** `helper-fixtures.R` loads the committed fixtures
  (`fixture()`, `msg_fixture()`, `decode_pool()`, `varint()`);
  `helper-entry-points.R` has the table of entry points the shared argument
  tests walk.
- **Runtime.** The design's target is under 15 s; it ran in 10.6 s
  installed when last measured (2026-11-05).
- **Dev builds differ from installed ones.** `devtools::load_all()` builds
  without `NDEBUG`, which brings `assert()` and upb's unreachable-failure
  path back. Judge symbols and compiled-code NOTEs on an `R CMD INSTALL`
  build; `test-symbols.R` skips dev builds.

## Continuous integration

The package calls r-actions' `r-cmd-check.yml@v1`, `coverage.yml` and
`cran-release.yml` (both pinned to a commit), and from `native-checks.yaml`
the sanitizers, valgrind, LTO, gctorture, rchk, analyzers and cran-special
workflows. Its own workflows:

- `conformance.yaml`: protobuf's conformance suite, built from the vendored
  tag, on pushes, pull requests and weekly.
- `hardening.yaml`: every fuzz target's canary must crash, then r-actions'
  `fuzz.yml` runs each target under libFuzzer, ASan and UBSan, five minutes
  a target on pull requests and pushes and an hour nightly. `fuzz_decode`
  and `fuzz_json` reach upb through the shim alone; `fuzz_build` embeds R
  to reach the code that builds R values and the encoder that walks them.
- `vendor.yaml`: r-actions' `vendor.yml`, which runs `tools/verify-vendor`.
- `vendor-upstream.yaml`: weekly, opens or updates an issue when protobuf
  releases a newer tag than the vendored one.

The local jobs in `conformance`, `hardening` and `vendor` are gated by
`changes.yml`. Deliberate deviations from `.claude/shared/ci.md`:

- **`coverage` and `pkgdown` ignore `CRAN-SUBMISSION` by `paths-ignore`**,
  because they run on documentation changes on purpose.
- **A push to `main` runs the full profile.** The callers pass `quick` only
  for a pull request without `full-ci`, not `profile: auto`. Don't wait on
  the full run a merge starts.
- **`pkgdown.yaml` is the scaffold's own r-lib workflow**, not an r-actions
  caller.

Commit `CRAN-SUBMISSION` on a branch and merge its pull request without
`[skip ci]`: every other workflow skips that change, and the push to `main`
is what runs `cran-release.yaml`.

## Vendored native code

upb, as protobuf's checked-in Ruby amalgamation (`src/vendor/upb/ruby-upb.{c,h}`),
plus `utf8_range` (`src/vendor/utf8_range/`), at protobuf `v36.2`
(BSD-3-Clause and MIT; `inst/COPYRIGHTS`). `src/vendor/PROVENANCE` records
the tag, commit, upstream hashes and patch series (`tools/patches/0001` to
`0008`). `tools/vendor-upb <tag>` re-vendors, `tools/verify-vendor` (run by
the `vendor` workflow) checks "upstream plus exactly these patches", and
`tools/make-pedantic-patch` regenerates `0003-pedantic.patch`. Design §9
says why each patch exists.

- **Never hand-edit `src/vendor/`.** Change a patch in `tools/patches/` and
  re-run `tools/vendor-upb`, or `tools/verify-vendor` fails.
