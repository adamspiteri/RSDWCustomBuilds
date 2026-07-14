#!/usr/bin/env python3
"""Clone a retoc legacy donor Blueprint with names swapped (no UAssetGUI).

This reproduces what the old UAssetGUI JSON clone did for piece BPs: a byte-faithful
copy of the donor BP (all snap sockets, colliders, stability config, components) with
ONLY the identity + mesh renamed:
  - package path            -> /Game/RSDWBuilds/<Id>/BP_<Id>
  - BP_T1_Wall_Large[_C]    -> BP_<Id>[_C]  (+ Default__ CDO name)
  - donor mesh pkg + asset  -> the piece's SM_<Id>

All FName INDICES are preserved (name-map strings renamed in place), so the uexp is
copied VERBATIM. Only the uasset changes: summary package string, name-map entries
(+ hashes), raw FString occurrences in the header tail (asset-registry block), and
every absolute offset / export SerialOffset shifted by the accumulated byte delta.

Summary layout (verified on 0.12.0.0 retoc extracts): the package path FString lives at
offset 52; every later field is positional AFTER it — never use absolute offsets.

Usage:
  clone_legacy_bp.py <donor.uasset> <donor.uexp> <out.uasset> <out.uexp> \
      <donor_pkg_path> <donor_name> <new_pkg_path> <new_name> \
      <donor_mesh_pkg> <donor_mesh_name> <new_mesh_pkg> <new_mesh_name>

Prints RSDW_CLONE_OK on success.
"""
from __future__ import annotations

import struct
import sys
from pathlib import Path

from ue_namemap_hash import generate_hash

PKG_STR_OFF = 52
# Field offsets RELATIVE to (52 + 4 + package_string_bytes) — verified against the
# catalogue (base 134): NameCount +4, NameOffset +8, ExportCount +28, ExportOffset +32,
# ImportCount +36, ImportOffset +40, other section offsets +16/+48/+56/+64/+140/+164,
# BulkDataStart(int64) +144.
REL_NAME_COUNT = 4
REL_NAME_OFFSET = 8
REL_EXPORT_COUNT = 28
REL_EXPORT_OFFSET = 32
REL_IMPORT_COUNT = 36
REL_OFFSET_FIELDS = (16, 32, 40, 48, 56, 64, 140, 164)
REL_BULK_START = 144


def read_fstr(d: bytes, off: int) -> tuple[str, int]:
    """Return (text, total_entry_len). Supports UTF-16 (negative len)."""
    ln = struct.unpack_from("<i", d, off)[0]
    if ln >= 0:
        raw = d[off + 4 : off + 4 + ln]
        text = raw[:-1].decode("utf-8") if raw.endswith(b"\x00") else raw.decode("utf-8")
        return text, 4 + ln
    n = -ln
    return d[off + 4 : off + 4 + n * 2 - 2].decode("utf-16-le"), 4 + n * 2


def fstr(text: str) -> bytes:
    raw = text.encode("utf-8") + b"\x00"
    return struct.pack("<i", len(raw)) + raw


def iter_names(src: bytes):
    pkg_len = read_fstr(src, PKG_STR_OFF)[1]
    base = PKG_STR_OFF + pkg_len
    count = struct.unpack_from("<i", src, base + REL_NAME_COUNT)[0]
    pos = struct.unpack_from("<i", src, base + REL_NAME_OFFSET)[0]
    for _ in range(count):
        text, total = read_fstr(src, pos)
        pos += total + 4
        yield text


def autodetect_mesh(src: bytes) -> tuple[str, str]:
    """Find the donor's single static-mesh reference in the name map."""
    names = list(iter_names(src))
    meshes = [n for n in names if n.startswith("SM_")]
    if len(meshes) != 1:
        raise SystemExit(f"ERROR: mesh auto-detect found {len(meshes)} SM_ names: {meshes} "
                         "- pass donor mesh explicitly")
    asset = meshes[0]
    pkgs = [n for n in names if n.startswith("/Game/") and n.endswith("/" + asset)]
    if len(pkgs) != 1:
        raise SystemExit(f"ERROR: mesh auto-detect found {len(pkgs)} package paths for {asset}")
    return pkgs[0], asset


def main() -> None:
    if len(sys.argv) != 13:
        print(__doc__)
        sys.exit(2)
    (uasset_in, uexp_in, uasset_out, uexp_out,
     donor_pkg, donor_name, new_pkg, new_name,
     donor_mesh_pkg, donor_mesh_name, new_mesh_pkg, new_mesh_name) = sys.argv[1:13]

    src = Path(uasset_in).read_bytes()
    uexp_len = Path(uexp_in).stat().st_size

    if donor_mesh_pkg == "auto" or donor_mesh_name == "auto":
        donor_mesh_pkg, donor_mesh_name = autodetect_mesh(src)
        print(f"auto-detected donor mesh: {donor_mesh_pkg} ({donor_mesh_name})")

    renames = {
        donor_pkg: new_pkg,
        donor_name: new_name,
        donor_name + "_C": new_name + "_C",
        "Default__" + donor_name + "_C": "Default__" + new_name + "_C",
        donor_mesh_pkg: new_mesh_pkg,
        donor_mesh_name: new_mesh_name,
    }

    # --- summary package string ---
    pkg_text, pkg_len = read_fstr(src, PKG_STR_OFF)
    if pkg_text != donor_pkg:
        raise SystemExit(f"ERROR: summary package is '{pkg_text}', expected '{donor_pkg}'")
    base_old = PKG_STR_OFF + pkg_len

    def rd(rel: int) -> int:
        return struct.unpack_from("<i", src, base_old + rel)[0]

    name_count = rd(REL_NAME_COUNT)
    name_off = rd(REL_NAME_OFFSET)
    export_count = rd(REL_EXPORT_COUNT)
    export_off = rd(REL_EXPORT_OFFSET)
    if not (0 < name_count < 100000 and 0 < name_off < len(src) and 0 < export_count < 10000):
        raise SystemExit(f"ERROR: implausible summary (names={name_count}@{name_off}, exports={export_count})")

    # --- rebuild name map with renames (indices preserved) ---
    entries = []
    pos = name_off
    renamed = 0
    for _ in range(name_count):
        text, total = read_fstr(src, pos)
        pos += total
        h = src[pos : pos + 4]
        pos += 4
        if text in renames:
            text = renames[text]
            h = struct.pack("<I", generate_hash(text))
            renamed += 1
        entries.append(fstr(text) + h)
    name_map_end_old = pos
    if renamed == 0:
        raise SystemExit("ERROR: no name-map entries matched the rename set")
    new_name_map = b"".join(entries)

    # --- find raw FString occurrences of donor names in the header tail (AR block) ---
    tail_old = src[name_map_end_old:]
    matches = []  # (pos_in_tail, old_pat, new_pat)
    for old, new in renames.items():
        pat = fstr(old)
        start = 0
        while True:
            i = tail_old.find(pat, start)
            if i < 0:
                break
            matches.append((i, pat, fstr(new)))
            start = i + len(pat)
    matches.sort(key=lambda m: m[0])
    # rebuild tail sequentially (original coordinates preserved in `matches`)
    tail_parts = []
    cur = 0
    for i, pat, rep in matches:
        if i < cur:
            continue  # overlapping match (shouldn't happen with exact FStrings)
        tail_parts.append(tail_old[cur:i])
        tail_parts.append(rep)
        cur = i + len(pat)
    tail_parts.append(tail_old[cur:])
    new_tail = b"".join(tail_parts)

    # --- assemble ---
    new_pkg_str = fstr(new_pkg)
    out = bytearray()
    out += src[:PKG_STR_OFF]
    out += new_pkg_str
    out += src[base_old:name_off]
    out += new_name_map
    out += new_tail

    base_new = PKG_STR_OFF + len(new_pkg_str)
    total_delta = len(out) - len(src)

    # splices in ORIGINAL file coordinates -> cumulative delta for any original offset
    splices = [(PKG_STR_OFF, len(new_pkg_str) - pkg_len),
               (name_off, len(new_name_map) - (name_map_end_old - name_off))]
    for i, pat, rep in matches:
        splices.append((name_map_end_old + i, len(rep) - len(pat)))
    splices.sort()

    def adjust(off: int) -> int:
        # STRICTLY BEFORE: an offset pointing at the start of a spliced region must not
        # be shifted by that region's own delta (e.g. NameOffset vs the name-map splice).
        return off + sum(d for (p, d) in splices if p < off)

    def wr(rel: int, value: int) -> None:
        struct.pack_into("<i", out, base_new + rel, value)

    # --- fix summary offsets ---
    struct.pack_into("<i", out, 44, len(out))  # TotalHeaderSize
    for rel in set(REL_OFFSET_FIELDS) | {REL_NAME_OFFSET}:
        v = rd(rel)
        if 0 < v <= len(src):
            wr(rel, adjust(v))
    bulk = struct.unpack_from("<q", src, base_old + REL_BULK_START)[0]
    if bulk > 0:
        struct.pack_into("<q", out, base_new + REL_BULK_START, bulk + total_delta)

    # --- fix export map SerialOffsets ---
    # Pin the SerialOffset field position using export 0: its value equals the OLD
    # TotalHeaderSize exactly (export data begins right after the header in cooked
    # split packages). Then apply the same in-entry offset to every export and demand
    # strictly increasing values inside [header, header+uexp).
    old_header = len(src)
    export_off_new = adjust(export_off)
    ends = sorted(v for v in (rd(r) for r in REL_OFFSET_FIELDS) if v > export_off) + [len(src)]
    entry_size = (ends[0] - export_off) // export_count
    if entry_size < 32 or entry_size > 256:
        raise SystemExit(f"ERROR: implausible export entry size {entry_size}")
    serial_fo = None
    for fo in range(0, entry_size - 7, 4):
        if struct.unpack_from("<q", out, export_off_new + fo)[0] == old_header:
            serial_fo = fo
            break
    if serial_fo is None:
        raise SystemExit("ERROR: could not locate SerialOffset field in export map")
    prev = -1
    for i in range(export_count):
        off = export_off_new + i * entry_size + serial_fo
        v = struct.unpack_from("<q", out, off)[0]
        if not (old_header <= v < old_header + uexp_len) or v <= prev:
            raise SystemExit(f"ERROR: export {i} SerialOffset {v} fails sanity check")
        prev = v
        struct.pack_into("<q", out, off, v + total_delta)

    Path(uasset_out).write_bytes(out)
    Path(uexp_out).write_bytes(Path(uexp_in).read_bytes())
    print(f"clone: {donor_name} -> {new_name}; {renamed} name-map renames, "
          f"{len(matches)} tail renames, delta {total_delta:+d} bytes, "
          f"{export_count} exports @serial_fo {serial_fo} refixed")
    print("RSDW_CLONE_OK")


if __name__ == "__main__":
    main()
