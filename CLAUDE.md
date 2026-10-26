# CLAUDE.md

<!-- markdownlint-disable-next-line MD013 -->
This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

zuproto decodes and encodes Protocol Buffers messages in R through upb, the
small C runtime under protobuf's Python, Ruby and PHP implementations. It works
from descriptor sets (`protoc --descriptor_set_out`, `buf build`), not
generated code: one message becomes a named list, many messages become a data
frame built column by column. It is a format package in the `zu*` family, like
zucbor and zumsgpack, except that every call names a message type in a
descriptor pool. upb and `utf8_range` are vendored, so there is no system
protobuf, `protoc` or Abseil. Hard runtime dependencies are zero: no `Imports`,
no `LinkingTo`; zuint and bit64 are in `Suggests` for 64-bit fields. It will
not generate R code per message type, parse `.proto` or text format, or speak
gRPC.

The specification is [`.agents/design.md`](.agents/design.md), adopted from
[RFC 0010](https://github.com/pedrobtz/packages/blob/main/rfcs/started/0010-zuproto-protocol-buffers.md).
It outranks this file: `CLAUDE.md` orients, the design doc decides. Its open
questions (§18) are still open.

## Current state

Scaffolded 2026-10-24 with `create-pkg.sh -c`; no functionality yet. The
roadmap in `.agents/roadmap.md` takes it to v0.1.0. Stage 0 is a go/no-go: if
the upb amalgamation cannot be made CRAN-clean with the design's two patches,
the design goes back to the maintainer before Stage 1.

## Stage tracking

Progress toward the next version is tracked as GitHub sub-issues, so the
parent issue shows a progress bar such as "6 of 7".

- **One parent issue per target version**, titled with the bare version, for
  example `v0.1.0`. `v0.1.0` issue: created by `pkg-roadmap`.
- **One sub-issue per roadmap stage**, titled as the roadmap titles it, for
  example `Stage 3 — R interface`, and linking to that section. The number of
  stages is whatever the roadmap has; there is no fixed scale.
- **Every tracking issue carries the `stage` label**, so it can be told apart
  from bug and feature issues and left out of open-issue counts.
- **Close a stage by merging its pull request.** Put `Closes #<n>` in the
  body of the stage's pull request. Never close a stage whose exit criteria
  are not met; record a deviation in the roadmap first.
- **The roadmap stays authoritative.** The issues record which stages are
  done, not what a stage requires. Adding, removing or renaming a stage
  means editing the roadmap and the sub-issues in the same change.
- **Each stage has a CI tier, `quick` or `full`.** The roadmap sets it, and
  `quick` is the default. See Continuous integration for what each means.
  The second-to-last stage, `Full CI`, runs the full set and fixes what it
  finds before `v0.1.0 readiness`.
- Close the parent issue when CRAN accepts the version and it is tagged.
  Opening a parent issue implies at least one stage sub-issue; a parent with
  no sub-issues shows no progress on the board.

## Versioning

A new package develops at `0.0.0.9000` and targets `0.1.0` for its first CRAN
release. Set `Version: 0.1.0` and the matching `NEWS.md` heading when the
package enters `Pre-flight`. Bump to `0.1.0.9000` only after CRAN accepts it,
never before: a `.9000` version above an unreleased `0.1.0` heading is wrong.

Until the first release the R API may change freely. Sibling packages can
still depend on this one before CRAN does, through `Remotes:` or `LinkingTo:`.
None does yet, and zuproto has no C API. A package that others wait on should
reach CRAN first.

## Commands

Run from the package root.

```sh
Rscript -e 'devtools::load_all()'                # compile src/ and load
Rscript -e 'devtools::document()'                # roxygen -> NAMESPACE, man/
Rscript -e 'devtools::test()'                    # full testthat suite
Rscript -e 'devtools::test(filter = "<name>")'   # one test file
Rscript -e 'devtools::test(shuffle = TRUE)'      # order independence
Rscript -e 'devtools::check()'                   # R CMD check
air format .                                     # format R sources
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

Grows as stages land; `.agents/design.md` §4 has the whole plan.

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
- **Message fixtures** come from Python `protobuf` 7.36.2 through
  `tools/make-fixtures.py` (it says how to set up the venv), stored as hex
  in `tests/testthat/fixtures/msg/` with a `MANIFEST.tsv`.
- **Test fixtures** are `protoc` output: edit
  `tests/testthat/fixtures/proto/*.proto`, run `tools/make-test-descriptors`,
  commit the `.binpb` files.

## Invariants that are easy to break

The design fixes these before any code exists. Add each further one when a
stage establishes it.

- **All upb calls go through `src/zpb_upb.h`.** No other file includes the
  vendored header, and a test enforces it. Otherwise a re-vendor, against
  upb's unstable API, means edits all over `src/`.
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
- **Vendored patches are only the two in the design (§9.2).** A patch that
  touches decoder logic is a reason to stop and report upstream.
- **A builder that fails returns `NULL` with its PROTECTs undone**, never
  `Rf_error()`: the entry point must hand the error back to R to raise with
  its class. Only out-of-memory and broken internal invariants call
  `Rf_error()` directly.
- **Iterators start at `ZPB_*_ITER_BEGIN`, not 0.** upb's begin values are
  `(size_t) -1`; 0 is a valid position.
- **Internal native symbols use `zpb_` / `ZPB_`**, not `zuproto_`, and
  `R_init_zuproto` is the only exported symbol (hidden visibility from
  Stage 0).

## Testing conventions

- **Self-sufficient.** Every test builds its own inputs inside the
  `test_that()` block. No file-scope objects.
- **Self-contained.** Global state goes through `withr::local_*()`, randomised
  input through `withr::local_seed()`. Tests write only under `tempdir()`.
- **Assert on condition classes, never message text.** Use
  `expect_error(..., class = "<pkg>_<kind>_error")`. Wording belongs in
  snapshot tests.
- **Order independence.** `devtools::test(shuffle = TRUE)` is part of the
  definition of done.
- **Borrow a conformance suite before writing one.** Mainstream
  implementations in Python, Java, Go or Node usually ship a test corpus.
  Use it as an oracle rather than inventing cases by hand. Here that is
  protobuf's `conformance_test_runner`, run against an R testee in CI only,
  with an expected-failure list that may only shrink; fixtures come from
  Python's `protobuf` and `protoc --encode`, never by hand.
- **Helpers live in `tests/testthat/helper-*.R`.** `helper-fixtures.R`
  loads the committed fixtures (`fixture()`, `msg_fixture()`,
  `decode_pool()`, `varint()`); `helper-entry-points.R` has the table of
  entry points the shared argument tests walk. Fixtures come from
  `tools/make-test-descriptors` (protoc) and `tools/make-fixtures.py`
  (Python's protobuf), with provenance and SHA-256 in
  `fixtures/DESCRIPTORS.tsv` and `fixtures/msg/MANIFEST.tsv`.
- **Keep the suite inside the CRAN time budget.** The design's target is
  under 15 s; it ran in 9.3 s installed when last measured (2026-10-26).

## Definition of done

`devtools::document()` and `devtools::check()` clean, meaning 0 errors, 0
warnings and 0 notes. The one allowed note is "New submission" before the first
release. `devtools::test(shuffle = TRUE)` green. CI green at the change's
tier: the quick profile for a `quick` roadmap stage or an ordinary pull
request, the full profile for a `full` stage, `Full CI`, and every release.
A user-facing change also needs a test, roxygen documentation and a `NEWS.md`
entry.

## Releasing to CRAN

- **CI is the pre-submission check.** The `pedrobtz/r-actions` R CMD check runs
  `--as-cran` on the CRAN-like runners and containers, and it replaces
  win-builder, the macOS builder and R-hub. None of them is a release step,
  and `cran-comments.md` lists the CI legs as its test environments.
- **Entering `Pre-flight`.** The roadmap's feature stages are done, the
  version is set as in Versioning, `NEWS.md` and `cran-comments.md` are
  written, and CI is green. Only submission work remains.
- **Before submitting,** run `pkg-critical-review` once the roadmap is
  implemented and fix what it files, then `pkg-cran-review`, and resolve
  every finding. Both skills are in `pedrobtz/r-skills`.
- **The pretest is automated and does not read `cran-comments.md`.** A NOTE
  that is explained but not fixed gets the upload archived. Fix the NOTE, as
  under Vendored native code, instead of justifying it.
- **After acceptance,** `pkg-post-cran` tags the submitted commit with the
  bare version, `0.1.0` (no `v`), publishes the GitHub release, bumps to
  `0.1.0.9000`, closes the version's parent issue and moves the board card.

## Editing rules

- roxygen comments are the source. Never edit `man/` or `NAMESPACE` by hand.
- Edit `README.Rmd`, not the generated `README.md`.
- Keep prose simple and short. One idea per sentence.
- Wrap roxygen text at 80 characters and run `air format .` on R sources.
- Use `lower_snake_case`, and prefix internal native symbols with `<pkg>_`.
- Keep hard runtime dependencies at zero unless a recorded design decision
  says otherwise.
- Export and document public functions. Do not create roxygen topics for
  internal ones.

## Continuous integration

Workflows come from `pedrobtz/r-actions`. Call those reusable workflows instead
of writing bespoke ones, and pin a released tag rather than `main`. Pin a
workflow that holds a write token, such as `coverage.yml`, to a commit, with
the tag in a comment. The `R-CMD-check` workflow must call `r-cmd-check.yml`,
because a hand-rolled one does not count as the pre-submission check. This
package calls `r-cmd-check.yml@v1` and `coverage.yml@v1`; `pkgdown.yaml` is the
scaffold's own r-lib workflow.

Small edits get a small run. The shared workflows look at the files a pull
request changes, compared with its merge base:

- **Markdown only**, such as `README.md`, `NEWS.md` or `cran-comments.md`,
  skips every check. Only coverage and the pkgdown site run.
- **`DESCRIPTION` or `README.Rmd` as well**, and nothing else, adds one R CMD
  check on Ubuntu R-release.
- **Any other file** runs everything.

So put a README or `DESCRIPTION` touch-up in its own pull request. Once a pull
request changes code, every later push to it runs every workflow.

### Quick by default, full by exception

The full profile is slow. gctorture at step 20 alone has taken 36 to 107
minutes on sibling packages. Waiting on it between roadmap stages was the
main thing slowing roadmaps down, so:

- **Pull requests run the quick profile.** It should finish in under five
  minutes. If it doesn't, raise gctorture's `quick-step` or trim
  `quick-containers` in the caller workflows; never cut the full profile.
- **A `full` roadmap stage takes the `full-ci` label** and merges only on a
  green full run. The roadmap gives the reason in the stage's `**CI.**`
  line, for example first compiled code, a `PROTECT` or finalizer change, a
  vendored library, or a Windows-only path.
- **Don't wait on the full run a merge starts** on the default branch, and
  cancel older full runs it supersedes. A failure that only the full set
  shows goes on the `Full CI` stage issue as a comment with the run link,
  and is fixed there. A failure the quick profile also shows is fixed now.
- **`Full CI` and `v0.1.0 readiness` wait** for a green full run on their
  merge commit, and the release commit always needs one.
- Locally, run `gctorture(TRUE)` on the code a C change touches when it is
  cheap; the full run is the authority.

## Vendored native code

upb, as protobuf's checked-in Ruby amalgamation (`src/vendor/upb/ruby-upb.{c,h}`),
plus `utf8_range` (`src/vendor/utf8_range/`), at protobuf `v36.2`
(BSD-3-Clause and MIT; `inst/COPYRIGHTS`). `src/vendor/PROVENANCE` records
the tag, commit, upstream hashes and patch series. `tools/vendor-upb <tag>`
re-vendors, `tools/verify-vendor` (run by the `vendor` workflow) checks
"upstream plus exactly these patches", and `tools/make-pedantic-patch`
regenerates `0003-pedantic.patch`. Design §9 says why each patch exists.

- **Never hand-edit `src/vendor/`.** Change a patch in `tools/patches/` and
  re-run `tools/vendor-upb`, or `tools/verify-vendor` fails.
- **`devtools::load_all()` builds without `NDEBUG`**, which brings `assert()`
  and upb's unreachable-failure path back. Judge symbols and compiled-code
  NOTEs on an `R CMD INSTALL` build; `test-symbols.R` skips dev builds.

- Pin a stable upstream release, never `master` or a release candidate.
- Record the tag, the commit and the checksums, and write down the update
  procedure so the next bump is mechanical.
- Keep upstream `LICENSE` and `NOTICE` under `src/vendor/<lib>/`, declare the
  vendored code in `DESCRIPTION` and `inst/COPYRIGHTS`.
- Keep the vendor tree clearly separated from first-party source, and record
  every local patch and why it exists.
- **CRAN's compiled-code check applies to vendored code too.** No `stdout` or
  `stderr`, no `printf`, `abort`, `exit` or system RNG may be linked, even
  behind a debug switch that never runs. Remove them with a patch in
  `tools/patches/`, list it in `src/vendor/PROVENANCE`, and make the
  vendor-verify script check "upstream plus exactly these patches". Avoid
  diagnostic-suppressing pragmas too, because they draw their own NOTE. zuhtml
  is the reference: `tools/patches/0002-no-stdio.patch` and
  `tools/verify-vendor`. zuxml's first upload was archived because it
  justified such a symbol instead of patching it.
- Guard against regressions in CI: run `nm -u` on the built objects and fail
  on any of those symbols, so an upstream bump cannot bring them back.

## Commits and pull requests

Short, imperative, sentence-case commit subjects, optionally scoped. Keep each
commit focused and do not sweep in unrelated files. A pull request explains the
user-visible outcome and the rationale, links related issues, lists the checks
that were run and the tests that were skipped, and flags platform-sensitive or
vendored changes. Performance claims need evidence.

Never commit or push to the default branch. Work on a branch, open a pull
request, and leave it for review. Do not merge a pull request unless you are
told to.

When you find a defect, in this package or in an upstream tool, open an issue
for it rather than only working around it.

## Working with skills

The portfolio's workflow skills live in `pedrobtz/r-skills` (`pkg-init`,
`pkg-roadmap`, `pkg-implement`, `pkg-critical-review`, `pkg-cran-review`,
`pkg-post-cran`, `pkg-readme`); the general process skills are
[Superpowers](https://github.com/obra/superpowers). `building-a-package.md`
in `pedrobtz/packages` walks through them in order. Both sets defer to this
file where they overlap, so the settlements are recorded here.

- **One design.** The specification is `.agents/design.md`, adopted from the
  package's RFC in `pedrobtz/packages/rfcs`. A package with an adopted design
  is past `brainstorming`; a design change goes through the RFC, not a new
  spec. Superpowers' default `docs/superpowers/specs/` is not used.
- **Plans at two levels.** `.agents/roadmap.md` holds the stages, one
  mergeable pull request each, with exit criteria and a CI tier
  (`pkg-roadmap`). Inside a stage, `writing-plans` breaks the work into
  tasks of one test cycle each, saved as `.agents/plans/stage-<n>.md`. The
  roadmap stays authoritative; a plan is scratch and is not kept in sync.
- **Build and merge.** `pkg-implement` runs the stage loop: branch
  `stage-<n>-<slug>` from the stage issue, implement the plan with
  `test-driven-development` (`Rscript -e 'devtools::test(filter = "<name>")'`
  is the red/green command), open the pull request, merge on green at the
  stage's CI tier. The confirmation the user gives at the start of that
  loop is the "told to merge" that Commits and pull requests requires, so
  the `finishing-a-development-branch` menu is not presented for stage
  pull requests. Any other pull request still waits for review.
- **Failures and claims.** A failing check or test goes through
  `systematic-debugging` before a fix. "Green", "done" and "ready for CRAN"
  are claimed only after `verification-before-completion`: run the command,
  read the output.
- **Review.** `requesting-code-review` gates tasks inside a stage.
  `pkg-critical-review` reviews the whole package once the roadmap is
  implemented, with Posit's reviewers, and files issues. CRAN's reviewer
  email and GitHub review threads go through `receiving-code-review`.
- **Keep scratch out of the tarball.** `R CMD build` reads `.Rbuildignore`,
  not `.gitignore`. It must list `^\.agents$`, `^\.superpowers$` (the
  Superpowers task ledger), `^\.worktrees$` (if git worktrees are kept in
  the package directory; a sibling directory avoids the question),
  `^\.claude$`, `^CLAUDE\.md$`, `^AGENTS\.md$`, `^CRAN-SUBMISSION$` and
  `^cran-comments\.md$`. A stray top-level file is a NOTE, and the pretest
  archives on NOTEs.
