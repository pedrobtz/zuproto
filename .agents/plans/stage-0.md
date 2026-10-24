# Stage 0 — Package identity: implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use
> superpowers:subagent-driven-development (recommended) or
> superpowers:executing-plans to implement this plan task-by-task. Steps use
> checkbox (`- [ ]`) syntax for tracking.

**Goal:** zuproto has its real identity and working CI, and nothing else.

**Architecture:** No functionality. `DESCRIPTION`, the three workflow
callers and two design records change; one test replaces the placeholder.

**Tech Stack:** R (>= 4.1), testthat 3, pedrobtz/r-actions v1.

**Spec:** `.agents/roadmap.md` § Stage 0; `.agents/design.md` §3, §14,
§18 question 1.

## Global Constraints

- `Depends: R (>= 4.1)`, `Language: en-GB`, no `Imports`, no `LinkingTo`.
- `R CMD check` NOTEs are failures (the pretest archives on NOTEs).
- Workflows call `pedrobtz/r-actions`; `coverage.yml` pinned to commit
  `8caf5119301bb2a3bd433b92045b8c75b3097096` (`# v1.24.0`), the others `@v1`.
- Quick-profile checks finish in under five minutes.

## Review Focus

- `Suggests` naming an unreleased package (zuint is 0.0.0.9000, on neither
  CRAN nor r-universe): a NOTE and a failed dependency install. Deferred to
  Stage 6 with bit64 and withr, where they are first used; recorded in the
  roadmap.
- The coverage badge push to `main` is rejected by the `main` ruleset
  (run 40126344488): it must go to `gh-pages`.
- The pkgdown deploy force-pushing over a badge commit: `force: false`.
- The Windows R-devel row must be added to `runners` without dropping the
  four default legs.

---

### Task 1: Identity in `DESCRIPTION` and a real first test

**Files:**

- Modify: `DESCRIPTION`
- Modify: `tests/testthat/test-zuproto.R` → rename to
  `tests/testthat/test-package.R`

- [ ] **Step 1: Replace the placeholder test** with
  `test_that("the package loads and registers its native library", …)`
  asserting `expect_true("zuproto" %in% loadedNamespaces())` and
  `expect_true(is.loaded("R_init_zuproto") || "zuproto" %in% names(getLoadedDLLs()))`;
  the second is the meaningful one: `expect_true("zuproto" %in% names(getLoadedDLLs()))`.
- [ ] **Step 2: `DESCRIPTION`**: Title `Protocol Buffers Decoding and Encoding
  with 'upb'`; Description per design §1 (descriptor sets, lists for one
  message, data frames for many, bundled upb so no system protobuf);
  `Authors@R` Pedro Baltazar `c("aut", "cre", "cph")` (upb's authors are
  added in Stage 1 with the vendored code); `URL` GitHub and pkgdown;
  `BugReports`; `Depends: R (>= 4.1)`; `Language: en-GB`;
  `Suggests: testthat (>= 3.0.0)`.
- [ ] **Step 3:** `Rscript -e 'devtools::document()'` then
  `Rscript -e 'devtools::test()'`: PASS.
- [ ] **Step 4: Commit** `Give zuproto its identity`.

### Task 2: CI callers

**Files:**

- Modify: `.github/workflows/R-CMD-check.yaml`
- Modify: `.github/workflows/coverage.yaml`
- Modify: `.github/workflows/pkgdown.yaml`

- [ ] **Step 1:** `R-CMD-check.yaml`: add `runners:` with the four defaults
  plus `{"os": "windows-latest", "r": "devel"}`.
- [ ] **Step 2:** `coverage.yaml`: pin to
  `@8caf5119301bb2a3bd433b92045b8c75b3097096 # v1.24.0`, add
  `badge-branch: gh-pages`, `badge-path: badges/coverage.svg`, and drop the
  `paths-ignore` filter.
- [ ] **Step 3:** `pkgdown.yaml`: on the deploy step add `force: false` and
  keep `clean: false`.
- [ ] **Step 4: Commit** `Run the coverage badge on gh-pages and check Windows R-devel`.

### Task 3: Records and roadmap

**Files:**

- Modify: `.agents/design.md` (§3, §18 question 1)
- Modify: `.agents/roadmap.md` (Stage 0, Stage 6, open questions)

- [ ] **Step 1:** Design: name check of 2026-10-24 (`zuproto` and `zupb`
  free on CRAN, r-universe and PyPI; `zuproto` kept); prefix check (`zpb_`
  appears in no sibling's source, by GitHub code search over `pedrobtz`).
- [ ] **Step 2:** Roadmap: dated deviation moving bit64, withr and zuint
  from Stage 0 to Stage 6 (withr to the first stage whose tests use it);
  open question: zuint must be on CRAN before zuproto 0.1.0 can suggest it.
- [ ] **Step 3: Commit** `Record the name and prefix checks`.

### Task 4: Verify

- [ ] `Rscript -e 'devtools::check()'`: 0 errors, 0 warnings, 0 notes
  (the "New submission" note excepted).
- [ ] `Rscript -e 'devtools::test(shuffle = TRUE)'`: PASS.
- [ ] Pull request quick profile: every check under five minutes.
