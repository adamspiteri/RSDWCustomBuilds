#!/usr/bin/env python3
"""Binary-patch retoc legacy DA_BuildPieceCatalogue_Default (no UAssetGUI).

Patches the split .uasset (name map) + .uexp (export serial) from a PRISTINE
retoc to-legacy extract. Inserts new FName strings at the export-data boundary
(same rule as patch_catalogue_012.py) and appends:
  1) SoftObject refs to CollectionBasicBuilding
  2) PersistenceID strings to AllPiecesInCatalogue

Usage (one piece):
  patch_legacy_catalogue.py <uasset> <uexp> <out.uasset> <out.uexp> \\
      <package_name> <asset_name> <collection_label> <persistence_id>

Prints CATALOGUE_INDEX|<piece_id>|index when persistence_id's basename is used as id hint.
"""
from __future__ import annotations

import struct
import sys
from pathlib import Path

from ue_namemap_hash import namemap_entry_bytes

# Vanilla 0.12 CollectionBasicBuilding SoftObject (pkg_idx, asset_idx) pairs.
# Verified against pristine retoc extract + UAssetAPI NameMap for game 0.12.0.0.
VANILLA_BASIC_BUILDING_IDX = (
    (342, 1124),  # DA_T1_Foundation_Large
    (337, 1119),  # DA_T1_Floor_Large
    (402, 1185),  # DA_T1_Stairs_Straight
    (407, 1187),  # DA_T1_Wall_Large
    (408, 1188),  # DA_T1_Wall_Large_Diagonal
    (410, 1190),  # DA_T1_Wall_Large_Doorframe
    (346, 1118),  # DA_T1_Door
    (348, 1131),  # DA_T1_Roof_Large_Diagonal
    (41, 849),  # BUILDPIECE_Prop_Torch
    (46, 854),  # BUILDPIECE_Prop_TorchStanding
)

NAME_COUNT_OFFS = (138, 226)
EXPORT_NAME_COUNT_OFF = 302
EXPORT_BOUNDARY_ANCHOR = b"/Script/CoreUObject"
# Legacy uasset summary fields that store absolute file offsets into the tail
# (misaligned int32s — discovered by diffing vanilla vs UAssetGUI fromjson).
FILE_OFFSET_FIELDS = (44, 150, 166, 174, 182, 190, 198, 274, 298)


def fstr_bytes(text: str) -> bytes:
    raw = text.encode("utf-8") + b"\x00"
    return struct.pack("<i", len(raw)) + raw


def namemap_name_bytes(text: str) -> bytes:
    return namemap_entry_bytes(text)


def read_fstring(data: bytes, off: int) -> tuple[str, int]:
    ln = struct.unpack_from("<i", data, off)[0]
    if ln == 0:
        return "", off + 4
    if ln < 0:
        ln = -ln
        end = off + 4 + ln * 2
        return data[off + 4 : end - 2].decode("utf-16-le"), end
    end = off + 4 + ln
    return data[off + 4 : end - 1].decode("utf-8"), end


def soft_elem(pkg_idx: int, asset_idx: int) -> bytes:
    return struct.pack("<IIIIi", pkg_idx, 0, asset_idx, 0, 0)


def name_map_bounds(uasset: bytes) -> tuple[int, int]:
    start = 318
    end = find_export_boundary_insert(uasset)
    if end <= start:
        raise SystemExit("ERROR: invalid name map bounds")
    return start, end


def build_name_index(uasset: bytes) -> dict[str, int]:
    start, end = name_map_bounds(uasset)
    pos = start
    idx = 0
    out: dict[str, int] = {}
    while pos < end:
        s, nxt = read_fstring(uasset, pos)
        if nxt <= pos:
            break
        out[s] = idx
        idx += 1
        pos = nxt
    return out


def name_index(uasset: bytes, text: str) -> int | None:
    return build_name_index(uasset).get(text)


def find_export_boundary_insert(uasset: bytes) -> int:
    pos = uasset.find(EXPORT_BOUNDARY_ANCHOR)
    if pos < 4:
        raise SystemExit("ERROR: export boundary anchor not found in uasset name map")
    return pos - 4  # FString length prefix


def find_basic_building_array(uexp: bytes) -> int:
    count = len(VANILLA_BASIC_BUILDING_IDX)
    pattern = struct.pack("<i", count) + b"".join(
        soft_elem(pi, ai) for pi, ai in VANILLA_BASIC_BUILDING_IDX
    )
    pos = uexp.find(pattern)
    if pos >= 0:
        return pos

    # Patched catalogues: count grows; locate via immutable vanilla prefix run.
    first = soft_elem(*VANILLA_BASIC_BUILDING_IDX[0])
    scan = 0
    while True:
        hit = uexp.find(first, scan)
        if hit < 0:
            break
        coll_pos = hit - 4
        if coll_pos < 0:
            scan = hit + 1
            continue
        ncount = struct.unpack_from("<i", uexp, coll_pos)[0]
        if ncount >= count:
            rel = hit
            ok = True
            for pi, ai in VANILLA_BASIC_BUILDING_IDX:
                if uexp[rel : rel + 20] != soft_elem(pi, ai):
                    ok = False
                    break
                rel += 20
            if ok:
                return coll_pos
        scan = hit + 1
    raise SystemExit("ERROR: CollectionBasicBuilding SoftObject array not found in uexp")


def find_all_pieces_array(uexp: bytes) -> int:
    """Pristine vanilla ships 755 persistence IDs (0.12.0.0)."""
    for count in (755, 756, 757, 758, 759, 760):
        pos = 0
        while True:
            pos = uexp.find(struct.pack("<i", count), pos)
            if pos < 0:
                break
            try:
                off = pos + 4
                for _ in range(min(3, count)):
                    _, off = read_fstring(uexp, off)
                if off > pos + 8:
                    return pos
            except Exception:  # noqa: BLE001
                pass
            pos += 1
    raise SystemExit("ERROR: AllPiecesInCatalogue array header not found in uexp")


def all_pieces_end(uexp: bytes, start: int) -> tuple[int, int]:
    count = struct.unpack_from("<i", uexp, start)[0]
    off = start + 4
    for _ in range(count):
        _, off = read_fstring(uexp, off)
    return count, off


def find_name_map_end(uasset: bytes) -> int:
    pos = 318
    count = struct.unpack_from("<i", uasset, NAME_COUNT_OFFS[0])[0]
    for _ in range(count):
        _, pos = read_fstring(uasset, pos)
    return pos


def read_preceding_namemap_name(uasset: bytes, insert_at: int) -> str | None:
    """Name string immediately before the export-boundary insert (hash slot at insert_at-4)."""
    hash_off = insert_at - 4
    if hash_off < 4:
        return None
    pos = hash_off - 4
    ln = struct.unpack_from("<i", uasset, pos)[0]
    if ln <= 0 or ln > 512 or pos + 4 + ln > hash_off:
        return None
    raw = uasset[pos + 4 : pos + 4 + ln]
    return raw[:-1].decode("utf-8") if raw.endswith(b"\x00") else raw.decode("utf-8")


def fix_preceding_name_hash(uasset: bytearray, insert_at: int) -> None:
    from ue_namemap_hash import generate_hash

    window = bytes(uasset[max(0, insert_at - 256) : insert_at])
    end = window.rfind(b"\x00")
    if end <= 0:
        return
    start = window.rfind(b"/Game", 0, end)
    if start < 0:
        start = window.rfind(b"DA_", 0, end)
    if start < 0:
        return
    try:
        name = window[start:end].decode("ascii")
    except UnicodeDecodeError:
        return
    if not name.isprintable():
        return
    struct.pack_into("<I", uasset, insert_at - 4, generate_hash(name))


def bump_package_size_refs(uasset: bytearray, old_len: int, new_len: int) -> None:
    """Replace stale total-size integers embedded in the export tail (e.g. @122621)."""
    if old_len == new_len:
        return
    pat = struct.pack("<i", old_len)
    rep = struct.pack("<i", new_len)
    off = 0
    while off <= len(uasset) - 4:
        if uasset[off : off + 4] == pat:
            uasset[off : off + 4] = rep
        off += 1


def sync_uexp_serial_size(uasset: bytearray, old_uexp_size: int, new_uexp_size: int) -> None:
    """Update the export map's SerialSize after growing the uexp.

    CRITICAL: SerialSize is an INT64 equal to (uexp length - 4); the uexp ends with the
    4-byte PACKAGE_FILE_TAG trailer that is NOT part of the export's serial data.
    (Searching for the raw uexp FILE length as int32 — the previous approach — matches
    nothing, leaves the header stale, and the game fatals with
    'Serial size mismatch: Expected read size N, Actual read size N+delta'.)
    """
    if old_uexp_size == new_uexp_size:
        return
    old_serial = struct.pack("<q", old_uexp_size - 4)
    new_serial = struct.pack("<q", new_uexp_size - 4)
    hits = []
    off = 0
    while True:
        off = bytes(uasset).find(old_serial, off)
        if off < 0:
            break
        hits.append(off)
        off += 1
    if not hits:
        raise SystemExit(
            f"ERROR: export SerialSize int64 ({old_uexp_size - 4}) not found in uasset - "
            "refusing to write a catalogue the game would reject"
        )
    for off in hits:
        uasset[off : off + 8] = new_serial
    print(
        f"SerialSize: {old_uexp_size - 4} -> {new_uexp_size - 4} "
        f"({len(hits)} occurrence(s) @ {hits})"
    )


# Summary field offsets (verified against pristine 0.12.0.0 retoc extract):
#   170 = ImportCount, 174 = ImportOffset, 278 = BulkDataStartOffset (int64)
IMPORT_COUNT_OFF = 170
IMPORT_OFFSET_OFF = 174
BULK_DATA_START_OFF = 278
IMPORT_ENTRY_SIZE = 32  # ClassPackage FName(8) + ClassName FName(8) + Outer(4) + ObjectName FName(8) + bOptional(4)


def bump_name_indices(uasset: bytearray, threshold: int, delta: int) -> None:
    """Bump FName indices >= threshold in the IMPORT MAP only.

    Names inserted at the export-data boundary shift the summary-only names
    (>= NamesReferencedFromExportDataCount) up by delta; imports reference those by
    index. NEVER blanket-rewrite the file tail: any unrelated int32 that happens to
    fall in the range (export map fields, asset-registry data, offsets) gets corrupted
    and the export data becomes unparseable.
    """
    if delta <= 0:
        return
    count = struct.unpack_from("<i", uasset, IMPORT_COUNT_OFF)[0]
    start = struct.unpack_from("<i", uasset, IMPORT_OFFSET_OFF)[0]
    if count <= 0 or count > 4096 or start <= 0 or start + count * IMPORT_ENTRY_SIZE > len(uasset):
        raise SystemExit(f"ERROR: implausible import map (count={count}, offset={start})")
    bumped = 0
    for i in range(count):
        base = start + i * IMPORT_ENTRY_SIZE
        for field_off in (0, 8, 20):  # ClassPackage, ClassName, ObjectName FName indices
            off = base + field_off
            v = struct.unpack_from("<i", uasset, off)[0]
            if v >= threshold:
                struct.pack_into("<i", uasset, off, v + delta)
                bumped += 1
    print(f"import map: bumped {bumped} FName index field(s) across {count} import(s)")


def sync_bulk_data_start(uasset: bytearray, serial_size: int) -> None:
    """BulkDataStartOffset (int64 @278) = TotalHeaderSize + export SerialSize."""
    new_val = len(uasset) + serial_size
    struct.pack_into("<q", uasset, BULK_DATA_START_OFF, new_val)
    print(f"BulkDataStartOffset -> {new_val}")


def bump_tail_offsets(uasset: bytearray, insert_at: int, delta: int) -> None:
    """Shift summary pointers that target bytes at/after the name-map insert."""
    old_len = len(uasset)
    for off in FILE_OFFSET_FIELDS:
        if off + 4 > old_len:
            continue
        v = struct.unpack_from("<i", uasset, off)[0]
        if insert_at <= v < old_len:
            struct.pack_into("<i", uasset, off, v + delta)


def patch_uasset_names(uasset: bytearray, new_names: list[str]) -> dict[str, int]:
    if not new_names:
        return {}
    insert_at = find_export_boundary_insert(uasset)
    blob = b"".join(namemap_name_bytes(n) for n in new_names)
    export_count = struct.unpack_from("<i", uasset, EXPORT_NAME_COUNT_OFF)[0]
    name_count = struct.unpack_from("<i", uasset, NAME_COUNT_OFFS[0])[0]
    assigned = {n: export_count + i for i, n in enumerate(new_names)}
    old_pkg_len = len(uasset)
    fix_preceding_name_hash(uasset, insert_at)
    bump_tail_offsets(uasset, insert_at, len(blob))
    uasset[insert_at:insert_at] = blob
    bump_name_indices(uasset, export_count, len(new_names))
    bump_package_size_refs(uasset, old_pkg_len, len(uasset))
    new_export = export_count + len(new_names)
    new_name = name_count + len(new_names)
    struct.pack_into("<i", uasset, EXPORT_NAME_COUNT_OFF, new_export)
    for off in NAME_COUNT_OFFS:
        struct.pack_into("<i", uasset, off, new_name)
    struct.pack_into("<i", uasset, 44, len(uasset))
    print(
        f"NameMap.insert@{export_count} +{len(new_names)} name(s); "
        f"export_count {export_count} -> {new_export}; delta={len(blob)}"
    )
    return assigned


def piece_already_in_collection(uexp: bytes, coll_pos: int, pkg_idx: int) -> bool:
    count = struct.unpack_from("<i", uexp, coll_pos)[0]
    rel = coll_pos + 4
    for _ in range(count):
        pi = struct.unpack_from("<I", uexp, rel)[0]
        if pi == pkg_idx:
            return True
        rel += 20
    return False


def persistence_index(uexp: bytes, all_pos: int, persist: str) -> int | None:
    count, off = all_pieces_end(uexp, all_pos)
    scan = all_pos + 4
    for i in range(count):
        s, scan = read_fstring(uexp, scan)
        if s == persist:
            return i
    return None


def main():
    if len(sys.argv) != 9:
        print(__doc__)
        sys.exit(2)
    uasset_in, uexp_in, uasset_out, uexp_out, pkg, asset, _label, persist = sys.argv[1:9]

    uasset = bytearray(Path(uasset_in).read_bytes())
    uexp = bytearray(Path(uexp_in).read_bytes())
    old_uexp_size = len(uexp)

    existing = {n for n in (pkg, asset) if fstr_bytes(n) in uasset}
    new_names = []
    for n in (pkg, asset):
        if n not in existing and n not in new_names:
            new_names.append(n)
    idx_map = patch_uasset_names(uasset, new_names)
    pkg_idx = idx_map.get(pkg)
    if pkg_idx is None:
        pkg_idx = name_index(uasset, pkg)
    asset_idx = idx_map.get(asset)
    if asset_idx is None:
        asset_idx = name_index(uasset, asset)
    if pkg_idx is None or asset_idx is None:
        raise SystemExit("ERROR: could not resolve name indices after insert")

    coll_pos = find_basic_building_array(uexp)
    if not piece_already_in_collection(uexp, coll_pos, pkg_idx):
        count = struct.unpack_from("<i", uexp, coll_pos)[0]
        insert = coll_pos + 4 + count * 20
        uexp[insert:insert] = soft_elem(pkg_idx, asset_idx)
        struct.pack_into("<i", uexp, coll_pos, count + 1)
        print(f"menu: appended {asset} to CollectionBasicBuilding (count {count} -> {count + 1})")
    else:
        print(f"menu: {asset} already present in CollectionBasicBuilding")

    all_pos = find_all_pieces_array(uexp)
    existing = persistence_index(uexp, all_pos, persist)
    if existing is not None:
        index = existing
        print(f"AllPiecesInCatalogue: {persist} already at index {index}")
    else:
        count, end = all_pieces_end(uexp, all_pos)
        uexp[end:end] = fstr_bytes(persist)
        struct.pack_into("<i", uexp, all_pos, count + 1)
        index = count
        print(f"AllPiecesInCatalogue: added {persist} at index {index} (count {count} -> {count + 1})")

    piece_id = asset.replace("DA_", "", 1) if asset.startswith("DA_") else asset
    print(f"CATALOGUE_INDEX|{piece_id}|{index}")

    Path(uexp_out).write_bytes(uexp)
    sync_uexp_serial_size(uasset, old_uexp_size, len(uexp))
    sync_bulk_data_start(uasset, len(uexp) - 4)
    Path(uasset_out).write_bytes(uasset)
    print(f"Wrote {uasset_out} ({len(uasset)} bytes) + {uexp_out} ({len(uexp)} bytes)")


if __name__ == "__main__":
    main()
