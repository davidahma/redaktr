#!/usr/bin/env python3
"""Verify the community app's exact sandbox entitlement set."""

import argparse
import plistlib
from pathlib import Path

EXPECTED = {
    "com.apple.security.app-sandbox",
    "com.apple.security.files.user-selected.read-write",
}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "plist",
        type=Path,
        nargs="?",
        default=Path("Apps/macOSApp/Redaktr/Redaktr/Redaktr.entitlements"),
    )
    args = parser.parse_args()
    with args.plist.open("rb") as f:
        actual = plistlib.load(f)
    if actual.keys() != EXPECTED or not all(value is True for value in actual.values()):
        parser.exit(1, "Unexpected entitlements. Expected sandbox and user-selected read/write only.\n")
    print(f"Validated offline sandbox entitlements in {args.plist}.")


if __name__ == "__main__":
    main()
