#!/usr/bin/env python3
"""
Minimal JVM HPROF histogram extractor.

Reads a standard (post-hprof-conv) JVM HPROF file and emits a CSV:
    class_name, instances, shallow_bytes

Designed for diffing Android heap dumps. Shallow size is approximated:
- INSTANCE_DUMP: payload bytes_size (does not include 16-byte object header
  on ART; we add a flat 16-byte estimate for parity with MAT/ART).
- OBJECT_ARRAY_DUMP: n * idsize + 16-byte header estimate.
- PRIMITIVE_ARRAY_DUMP: n * elem_size + 16-byte header estimate. We map
  element type code -> "[X" Java class name so primitive arrays surface
  in the histogram per element type (byte[], int[], ...).

Run:
    python3 hprof_histogram.py input.hprof out.csv
"""

import csv
import struct
import sys
from collections import defaultdict


# JVM HPROF type codes
TYPE_OBJECT = 2
TYPE_BOOL = 4
TYPE_CHAR = 5
TYPE_FLOAT = 6
TYPE_DOUBLE = 7
TYPE_BYTE = 8
TYPE_SHORT = 9
TYPE_INT = 10
TYPE_LONG = 11

PRIMITIVE_SIZE = {
    TYPE_BOOL: 1, TYPE_CHAR: 2, TYPE_FLOAT: 4, TYPE_DOUBLE: 8,
    TYPE_BYTE: 1, TYPE_SHORT: 2, TYPE_INT: 4, TYPE_LONG: 8,
}

PRIMITIVE_ARRAY_NAME = {
    TYPE_BOOL: "boolean[]", TYPE_CHAR: "char[]", TYPE_FLOAT: "float[]",
    TYPE_DOUBLE: "double[]", TYPE_BYTE: "byte[]", TYPE_SHORT: "short[]",
    TYPE_INT: "int[]", TYPE_LONG: "long[]",
}

OBJ_HEADER_BYTES = 16  # ART object header estimate
ARR_HEADER_BYTES = 16  # ART array header estimate (length + class ref)


def field_size(ftype: int, idsize: int) -> int:
    if ftype == TYPE_OBJECT:
        return idsize
    return PRIMITIVE_SIZE[ftype]


def parse(path: str):
    strings: dict[int, str] = {}
    class_name_id: dict[int, int] = {}   # class_object_id -> name_string_id
    counts: dict[int, int] = defaultdict(int)
    shallow: dict[int, int] = defaultdict(int)
    # Synthetic IDs for primitive arrays — high numeric range, won't collide
    PRIM_ARR_BASE = -1000
    prim_name_for_synthetic = {PRIM_ARR_BASE - t: n for t, n in PRIMITIVE_ARRAY_NAME.items()}

    with open(path, "rb") as f:
        # Header: "JAVA PROFILE 1.0.X\0"
        magic = bytearray()
        while True:
            c = f.read(1)
            if not c:
                raise ValueError("unexpected EOF in header")
            if c == b"\x00":
                break
            magic += c
        idsize = struct.unpack(">I", f.read(4))[0]
        f.read(8)  # timestamp

        while True:
            head = f.read(9)
            if len(head) < 9:
                break
            tag, _tdelta, length = struct.unpack(">BII", head)
            body = f.read(length)
            if len(body) != length:
                break

            if tag == 0x01:  # STRING_IN_UTF8
                sid = int.from_bytes(body[:idsize], "big")
                strings[sid] = body[idsize:].decode("utf-8", errors="replace")

            elif tag == 0x02:  # LOAD_CLASS
                #   serial(4) class_id(idsize) stack(4) name_id(idsize)
                class_id = int.from_bytes(body[4 : 4 + idsize], "big")
                name_off = 4 + idsize + 4
                name_id = int.from_bytes(body[name_off : name_off + idsize], "big")
                class_name_id[class_id] = name_id

            elif tag in (0x0C, 0x1C):  # HEAP_DUMP / HEAP_DUMP_SEGMENT
                parse_heap_segment(body, idsize, counts, shallow, PRIM_ARR_BASE)

    # Build name-indexed histogram
    hist: dict[str, tuple[int, int]] = {}
    for cid, n in counts.items():
        if cid <= PRIM_ARR_BASE:
            name = prim_name_for_synthetic.get(cid, f"<prim?{cid}>")
        else:
            name_id = class_name_id.get(cid)
            name = strings.get(name_id, f"<unknown:{cid:#x}>") if name_id else f"<noload:{cid:#x}>"
            name = name.replace("/", ".")
        hist[name] = (hist.get(name, (0, 0))[0] + n,
                      hist.get(name, (0, 0))[1] + shallow[cid])
    return hist


def parse_heap_segment(body: bytes, idsize: int,
                       counts: dict[int, int],
                       shallow: dict[int, int],
                       prim_arr_base: int) -> None:
    p = 0
    L = len(body)
    # Root tags + their payload sizes after the leading 1-byte subtag
    ROOT_FIXED = {
        0xFF: idsize,                          # ROOT_UNKNOWN
        0x01: idsize + idsize,                 # ROOT_JNI_GLOBAL: id + jni_ref
        0x02: idsize + 4 + 4,                  # ROOT_JNI_LOCAL: id + thread_serial + frame_num
        0x03: idsize + 4 + 4,                  # ROOT_JAVA_FRAME
        0x04: idsize + 4,                      # ROOT_NATIVE_STACK
        0x05: idsize,                          # ROOT_STICKY_CLASS
        0x06: idsize + 4,                      # ROOT_THREAD_BLOCK
        0x07: idsize,                          # ROOT_MONITOR_USED
        0x08: idsize + 4 + 4,                  # ROOT_THREAD_OBJECT
        # Less common — some Android exports use these. Skip with right widths.
        0x89: idsize + 4 + 4,                  # ROOT_INTERNED_STRING (Android variant)
        0x8A: idsize,                          # ROOT_FINALIZING
        0x8B: idsize,                          # ROOT_DEBUGGER
        0x8C: idsize,                          # ROOT_REFERENCE_CLEANUP
        0x8D: idsize,                          # ROOT_VM_INTERNAL
        0x8E: idsize + 4 + 4,                  # ROOT_JNI_MONITOR
        0x8F: idsize,                          # UNREACHABLE
    }

    while p < L:
        subtag = body[p]
        p += 1
        if subtag in ROOT_FIXED:
            p += ROOT_FIXED[subtag]

        elif subtag == 0x20:  # CLASS_DUMP — variable length
            #   class_obj_id(id) stack(4) super(id) loader(id) signers(id)
            #   domain(id) reserved(id) reserved(id) instance_size(4)
            #   const_pool_count(2) [{ idx(2) type(1) value(...) }]*
            #   statics_count(2)    [{ name_id(id) type(1) value(...) }]*
            #   inst_fields_count(2)[{ name_id(id) type(1) }]*
            p += idsize + 4 + idsize * 6 + 4
            n_pool = int.from_bytes(body[p : p + 2], "big"); p += 2
            for _ in range(n_pool):
                p += 2
                ftype = body[p]; p += 1
                p += field_size(ftype, idsize)
            n_stat = int.from_bytes(body[p : p + 2], "big"); p += 2
            for _ in range(n_stat):
                p += idsize
                ftype = body[p]; p += 1
                p += field_size(ftype, idsize)
            n_inst = int.from_bytes(body[p : p + 2], "big"); p += 2
            p += n_inst * (idsize + 1)

        elif subtag == 0x21:  # INSTANCE_DUMP
            #   id(id) stack(4) class_id(id) bytes(4) [bytes]
            p += idsize + 4
            class_id = int.from_bytes(body[p : p + idsize], "big"); p += idsize
            n_bytes = int.from_bytes(body[p : p + 4], "big"); p += 4
            p += n_bytes
            counts[class_id] += 1
            shallow[class_id] += n_bytes + OBJ_HEADER_BYTES

        elif subtag == 0x22:  # OBJECT_ARRAY_DUMP
            #   id(id) stack(4) num(4) elem_class_id(id) [ids]
            p += idsize + 4
            n_elem = int.from_bytes(body[p : p + 4], "big"); p += 4
            elem_class = int.from_bytes(body[p : p + idsize], "big"); p += idsize
            p += n_elem * idsize
            counts[elem_class] += 1
            shallow[elem_class] += n_elem * idsize + ARR_HEADER_BYTES

        elif subtag == 0x23:  # PRIMITIVE_ARRAY_DUMP
            #   id(id) stack(4) num(4) type(1) [elements]
            p += idsize + 4
            n_elem = int.from_bytes(body[p : p + 4], "big"); p += 4
            ptype = body[p]; p += 1
            esize = PRIMITIVE_SIZE[ptype]
            p += n_elem * esize
            key = prim_arr_base - ptype
            counts[key] += 1
            shallow[key] += n_elem * esize + ARR_HEADER_BYTES

        else:
            raise ValueError(f"Unknown sub-tag 0x{subtag:02x} at offset {p - 1}")


def main():
    if len(sys.argv) != 3:
        sys.exit("usage: hprof_histogram.py <input.hprof> <output.csv>")
    hist = parse(sys.argv[1])
    with open(sys.argv[2], "w", encoding="utf-8", newline="") as f:
        w = csv.writer(f)
        w.writerow(["class", "instances", "shallow_bytes"])
        for name, (n, sz) in sorted(hist.items(), key=lambda kv: -kv[1][1]):
            w.writerow([name, n, sz])
    print(f"wrote {sys.argv[2]} — {len(hist)} classes", file=sys.stderr)


if __name__ == "__main__":
    main()
