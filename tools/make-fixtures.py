#!/usr/bin/env python3
"""Write the message fixtures test-decode.R checks (design section 15).

Messages are built from protobuf JSON with Python's protobuf, an
independent implementation, never written by hand. Run from the package
root, with the pinned protobuf release that matches the vendored tag:

    python3 -m venv /tmp/zpb-venv
    /tmp/zpb-venv/bin/pip install 'protobuf==7.36.2'
    /tmp/zpb-venv/bin/python tools/make-fixtures.py

It writes tests/testthat/fixtures/msg/<name>.hex, the message's bytes as
lower-case hex (R CMD check takes some short binary files for executables),
and MANIFEST.tsv, with each message's type, source and SHA-256; and
tests/testthat/fixtures/{cycle,unresolved}.binpb, descriptor sets protoc
would refuse to write. Re-run after changing the fixture
schemas (tools/make-test-descriptors) or the messages below.
"""

import hashlib
import os

import google.protobuf
from google.protobuf import (  # noqa: F401  loads the well-known types
    any_pb2,
    descriptor_pb2,
    descriptor_pool,
    duration_pb2,
    empty_pb2,
    field_mask_pb2,
    json_format,
    message_factory,
    struct_pb2,
    timestamp_pb2,
    wrappers_pb2,
)

FIXTURES = "tests/testthat/fixtures"
OUT = os.path.join(FIXTURES, "msg")
EXPECTED = "7.36.2"

if google.protobuf.__version__ != EXPECTED:
    raise SystemExit(
        f"protobuf {google.protobuf.__version__} found; {EXPECTED} expected"
    )

pool = descriptor_pool.Default()
for name in ("decode", "decode2"):
    with open(os.path.join(FIXTURES, f"{name}.binpb"), "rb") as f:
        fds = descriptor_pb2.FileDescriptorSet.FromString(f.read())
    for file in fds.file:
        pool.Add(file)


def message(type_name, data):
    cls = message_factory.GetMessageClass(pool.FindMessageTypeByName(type_name))
    return json_format.ParseDict(data, cls(), descriptor_pool=pool)


# name: (type, JSON, bytes appended after serialising, note)
FIXTURES_MSG = {
    "scalars_set": ("zpb.decode.Scalars", {
        "fDouble": 1.5, "fFloat": 0.25, "fInt32": -42, "fSint32": -7,
        "fSfixed32": 123, "fUint32": 4000000000, "fFixed32": 3000000000,
        "fInt64": "-1234567890123", "fUint64": "9007199254740992",
        "fSint64": "-5", "fFixed64": "1", "fSfixed64": "-2", "fBool": True,
        "fString": "héllo ✓", "fBytes": "AAEC/w==", "fEnum": "HIGH",
        "fOptional": 0,
    }),
    "scalars_empty": ("zpb.decode.Scalars", {}),
    "scalars_big": ("zpb.decode.Scalars", {
        "fInt64": "9223372036854775807", "fUint64": "18446744073709551615",
        "fInt32": -2147483648, "fSint32": -2147483648,
    }),
    "repeated": ("zpb.decode.Repeated", {
        "packed": [1, 2, 3], "unpacked": [4, 5], "strings": ["a", "b"],
        "blobs": ["AQ==", "Ag=="], "levels": ["LOW", "HIGH"],
        "points": [{"x": 1, "y": 2}, {"x": 3, "y": 4, "next": {"x": 5}}],
        "flags": [True, False],
    }),
    "maps": ("zpb.decode.Maps", {
        "byString": {"b": 2, "a": 1},
        "byInt32": {"10": "ten", "-1": "minus", "2": "two"},
        "byInt64": {"9007199254740993": "big", "1": "one"},
        "byBool": {"true": "t", "false": "f"},
        "points": {"7": {"x": 7}},
        "levels": {"z": "LOW", "y": "HIGH"},
    }),
    "choice_text": ("zpb.decode.Choice", {"text": "hi", "other": "o"}),
    "choice_point": ("zpb.decode.Choice", {"point": {"x": 1}}),
    "choice_none": ("zpb.decode.Choice", {"other": "o"}),
    "uint64_keys": ("zpb.decode.Uint64Keys", {
        "byUint64": {"18446744073709551615": "max", "1": "one",
                     "9223372036854775808": "2^63"},
    }),
    "outer": ("zpb.decode.Outer", {
        "inner": {"text": "hi"},
        "items": [{"number": "3"}, {"point": {"x": 1}}, {"other": "o"}],
    }),
    "wellknown": ("zpb.decode.WellKnown", {
        "when": "2026-10-25T12:34:56.123456789Z", "took": "90.5s",
        "i32": -3, "i64": "12", "u32": 4000000000, "u64": "5",
        "f32": 1.5, "f64": 2.5, "flag": True, "text": "w", "blob": "AAE=",
        "meta": {"a": 1, "b": [True, None, "x"], "c": {"d": "e"}},
        "value": "str", "list": [1, "two", None],
        "any": {"@type": "type.googleapis.com/zpb.decode.Point",
                "x": 1, "y": 2},
        "mask": "a.b,c", "empty": {},
        "times": ["1970-01-01T00:00:00Z", "2000-01-01T00:00:00.500Z"],
    }),
    "nested_3": ("zpb.decode.Nested", {
        "depth": 1, "child": {"depth": 2, "child": {"depth": 3}},
    }),
    "legacy_min": ("zpb.decode2.Legacy", {"id": 1}),
    "legacy_ext": ("zpb.decode2.Legacy", {
        "id": 2, "name": "x", "values": [3],
        "[zpb.decode2.tag]": "t", "[zpb.decode2.codes]": [1, 2],
    }),
    # Field 99 is not in Point: varint tag 99 << 3 = 792 (0x98 0x06), value 5.
    "unknown_field": ("zpb.decode.Point", {"x": 1}, b"\x98\x06\x05",
                      "plus unknown field 99 = 5"),
}

os.makedirs(OUT, exist_ok=True)
rows = []
for name, spec in FIXTURES_MSG.items():
    type_name, data = spec[0], spec[1]
    extra = spec[2] if len(spec) > 2 else b""
    note = spec[3] if len(spec) > 3 else ""
    raw = message(type_name, data).SerializeToString(deterministic=True) + extra
    with open(os.path.join(OUT, f"{name}.hex"), "w") as f:
        f.write(raw.hex() + "\n")
    source = f"python-protobuf {EXPECTED} json_format.ParseDict"
    if note:
        source += f", {note}"
    rows.append((name, type_name, source, hashlib.sha256(raw).hexdigest()))

with open(os.path.join(OUT, "MANIFEST.tsv"), "w") as f:
    f.write("name\ttype\tsource\tsha256\n")
    for row in rows:
        f.write("\t".join(row) + "\n")
print(f"==> wrote {len(rows)} messages to {OUT}")


# Descriptor sets protoc refuses to write, for the pool's error paths
# (#42), built with descriptor_pb2 rather than by hand.
def file_set(*files):
    fds = descriptor_pb2.FileDescriptorSet()
    for name, deps, messages in files:
        f = fds.file.add(name=name, package="zpb.bad", syntax="proto3")
        f.dependency.extend(deps)
        for msg_name, fields in messages:
            m = f.message_type.add(name=msg_name)
            for field_name, number, type_name in fields:
                m.field.add(
                    name=field_name, number=number,
                    label=descriptor_pb2.FieldDescriptorProto.LABEL_OPTIONAL,
                    type=descriptor_pb2.FieldDescriptorProto.TYPE_MESSAGE,
                    type_name=type_name,
                )
    return fds.SerializeToString(deterministic=True)


BAD_SETS = {
    # a.proto and b.proto import each other.
    "cycle": file_set(("a.proto", ["b.proto"], [("A", [])]),
                      ("b.proto", ["a.proto"], [("B", [])])),
    # A field of a message type no file defines: upb rejects the file.
    "unresolved": file_set(
        ("unresolved.proto", [], [("M", [("x", 1, ".zpb.bad.Missing")])])),
}
for name, data in BAD_SETS.items():
    with open(os.path.join(FIXTURES, f"{name}.binpb"), "wb") as f:
        f.write(data)
print(f"==> wrote {len(BAD_SETS)} descriptor sets protoc would refuse")
