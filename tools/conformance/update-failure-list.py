#!/usr/bin/env python3
"""Rewrite tools/conformance/failure_list.txt from a conformance run's log,
grouping each failing test under the reason zuproto fails it (design
section 15). Run from the package root:

    : > tools/conformance/failure_list.txt
    CONFORMANCE_RUNNER=... tools/conformance/run > run.log 2>&1
    python3 tools/conformance/update-failure-list.py run.log

It stops if a failure fits none of the known reasons: that is a bug to fix
or a decision to record, not a line to add.
"""

import re
import sys

log = open(sys.argv[1]).read().splitlines()
fails = sorted({(m.group(1), m.group(2)) for l in log
                if (m := re.match(r"^  ((?:Required|Recommended)\.\S+) # (.*)$", l))})
passed = next((int(m.group(1)) for l in log
               if (m := re.search(r"CONFORMANCE SUITE \w+: (\d+) successes", l))), 0)

groups = {
    "int": ("Design 6.1, decided 2026-10-25: an int32, sint32 or sfixed32 value of -2^31 is\n"
            "# R's NA, so it decodes as NA with a warning and re-encodes as unset (or, inside a\n"
            "# repeated field, cannot be re-encoded).", []),
    "time": ("Design 6.3: Timestamp is POSIXct and Duration difftime, doubles rounded to the\n"
             "# microsecond, so nanosecond values and the extremes of the ranges do not\n"
             "# round-trip through R, and invalid nanos are normalised instead of refused.", []),
    "nul": ("Design 6.1, decided 2026-10-25: a string with a NUL byte cannot be an R\n"
            "# string; it is zuproto_unrepresentable.", []),
    "upbjson": ("upb's JSON decoder: protobuf's Ruby and PHP lists, which also use it, record\n"
                "# the same failures.", []),
}
other = []
for name, why in fails:
    if "EmbeddedNull" in name:
        groups["nul"][1].append((name, why))
    elif "QuotedExponential" in name or "AnyWithNoType" in name:
        groups["upbjson"][1].append((name, why))
    elif re.search(r"Timestamp|Duration", name) or re.search(r"optional_(timestamp|duration)", why):
        groups["time"][1].append((name, why))
    elif re.search(r"(INT32|SINT32|SFIXED32)", name) or "-2147483648" in why or re.search(r"Int32Field(Min|Max)", name):
        groups["int"][1].append((name, why))
    else:
        other.append((name, why))
if other:
    sys.exit("failures that fit no known reason:\n" + "\n".join(f"  {n} # {w}" for n, w in other))

n = sum(len(items) for _, items in groups.values())
out = ["# Conformance tests zuproto is expected to fail, with why (design section 15).",
       "# The list may only shrink: tools/conformance/run fails if a test here passes.",
       "# Written by tools/conformance/update-failure-list.py: "
       f"{n} of {passed + n} tests.", ""]
for comment, items in groups.values():
    if items:
        out.append("# " + comment)
        out += [f"{name} # {why}" for name, why in items]
        out.append("")
open("tools/conformance/failure_list.txt", "w").write("\n".join(out))
print({k: len(v[1]) for k, v in groups.items()})
