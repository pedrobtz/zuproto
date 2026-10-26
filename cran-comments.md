# zuproto 0.1.0, first submission

## R CMD check results

0 errors | 0 warnings | 1 note

* This is a new submission.

## Test environments

The package's continuous integration (pedrobtz/r-actions) runs `R CMD check
--as-cran` on:

* macOS, Windows and Ubuntu, R-release; Ubuntu, R-oldrel-1; Windows,
  R-devel;
* the R-hub `clang23`, `ubuntu-clang` and `ubuntu-gcc16` R-devel containers;
* without suggested packages (`nosuggests`) and without long doubles
  (`nold`).

It also runs the package under ASan, UBSan, valgrind, gctorture, rchk and
LTO, and Protocol Buffers' own conformance suite.

## Bundled code

The package bundles the 'upb' runtime and 'utf8_range' from the Protocol
Buffers release v36.2 (Google LLC; BSD-3-Clause; 'utf8_range' also MIT,
Yibo Cai), in `src/vendor/`. `inst/COPYRIGHTS` and `src/vendor/PROVENANCE`
record the upstream files, their hashes and the local patches, which keep
the compiled code free of `stderr`, `abort()` and diagnostic pragmas and
fix four issues that sanitizers and fuzzing found, three of them reported
upstream (protocolbuffers/protobuf#31030, #31031, #31032).

## Method References

There is no published paper describing the methods. The package implements
the Protocol Buffers binary wire format and JSON mapping, as specified at
<https://protobuf.dev/programming-guides/encoding/> and
<https://protobuf.dev/programming-guides/json/>.
