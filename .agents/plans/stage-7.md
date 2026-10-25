# Stage 7 — Conformance, fuzzing and hostile inputs: implementation plan

> Written after the fact; the stage followed the roadmap and design §15
> and §16.

1. Conformance: `tools/conformance/` (descriptor set from the pinned tag,
   R testee routing every payload through `proto_decode()` and
   `proto_encode()`, `run`, a failure list with a reason per group);
   `.github/workflows/conformance.yaml` builds the runner with CMake,
   cached by tag.
2. Fuzzing: `tools/fuzz/` targets `fuzz_decode`, `fuzz_json` (upb through
   the shim) and `fuzz_build` (embedded R), canaries, seeds from the
   fixtures, a standalone driver for Apple clang; `tools/run-fuzz`;
   `.github/workflows/hardening.yaml` (canaries, then r-actions' fuzz.yml).
3. Fix what they find: patch 0006; NaN on encode; NULL in `Value`
   fields; Timestamp and Duration ranges on binary encode.
4. Hostile inputs of §15: already tests (Stages 2, 3, 5).
5. Benchmarks against RProtoBuf: `tools/run-benchmarks`, recorded in §16.
