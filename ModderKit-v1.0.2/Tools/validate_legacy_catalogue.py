#!/usr/bin/env python3
"""Validate a binary-patched legacy catalogue before shipping (no UAssetGUI required).

Checks uexp menu array + persistence IDs and uasset name-map counts.
Exit 0 if OK, 1 if not.
"""
import struct
import sys

import patch_legacy_catalogue as plc


def main():
    if len(sys.argv) < 4:
        print("Usage: validate_legacy_catalogue.py <uasset> <uexp> <expected_piece_count> "
              "[persistence_id ...]")
        sys.exit(2)
    uasset_path, uexp_path, expected = sys.argv[1:4]
    expected = int(expected)
    persistence_ids = sys.argv[4:4 + expected]
    uasset = open(uasset_path, "rb").read()
    uexp = open(uexp_path, "rb").read()

    coll_pos = plc.find_basic_building_array(uexp)
    coll_count = struct.unpack_from("<i", uexp, coll_pos)[0]
    if coll_count < 10 + expected:
        print(f"FAIL: CollectionBasicBuilding count {coll_count} < {10 + expected}")
        sys.exit(1)

    # Persistence IDs are appended as plain FStrings — verify as raw bytes (robust vs array scan).
    for pid_str in persistence_ids:
        pid = pid_str.encode("ascii") + b"\x00"
        if pid not in uexp:
            print(f"FAIL: persistence id missing from uexp: {pid_str}")
            sys.exit(1)

    if uasset.find(plc.EXPORT_BOUNDARY_ANCHOR) < 0:
        print("FAIL: export boundary anchor missing from uasset")
        sys.exit(1)

    # THE check that catches the in-game fatal ("Serial size mismatch"): the export map's
    # SerialSize (int64) must equal the uexp length minus the 4-byte PACKAGE_FILE_TAG.
    expected_serial = struct.pack("<q", len(uexp) - 4)
    if expected_serial not in uasset:
        print(f"FAIL: export SerialSize int64 ({len(uexp) - 4}) not present in uasset "
              "(stale serial size - game would crash with Serial size mismatch)")
        sys.exit(1)

    export_count = struct.unpack_from("<i", uasset, plc.EXPORT_NAME_COUNT_OFF)[0]
    name_count = struct.unpack_from("<i", uasset, plc.NAME_COUNT_OFFS[0])[0]
    if export_count < 1513 + expected * 2 or name_count < 1538 + expected * 2:
        print(f"FAIL: name/export counts too low (names={name_count}, export={export_count})")
        sys.exit(1)

    print(
        f"OK: menu={coll_count} persist_ids={expected} "
        f"names={name_count} export={export_count}"
    )
    sys.exit(0)


if __name__ == "__main__":
    main()
