# Stage 5 — Data frames and delimited streams: implementation plan

> Written after the fact: the stage was built directly from the roadmap
> and design §6.2, §6.4 and §10 once question 6 was decided.

**Goal:** many messages, or one message's repeated message field, decode
into a data frame built column by column; delimited streams read and write.

1. Shim: oneof iteration for `<oneof>_case` columns.
2. `build_frame()` in `src/zpb_build.c`: one column per field, extension
   and real oneof, filled across rows; `rows[i]` `NULL` for a missing
   nested message; recursion only where some row sets the field.
3. `zpb_decode_df()`: modes list, `field`, delimited (framing in C,
   `consumed` returned for chunking); `zpb_frame_delimited()`.
4. `R/frame.R`: `proto_decode_df()`, `proto_read_delimited()` with `each`
   and `chunk_rows`, `proto_write_delimited()` from a data frame or list.
5. Tests: each row re-encodes to the single-message bytes; column shapes;
   `field`; index on failure; row limit; streams ending inside a varint
   or a message; chunks. Benchmark with `tools/run-benchmarks`.
