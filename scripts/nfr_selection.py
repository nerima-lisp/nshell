#!/usr/bin/env python3
"""Parse workflow selections for NFR performance measurements."""

from __future__ import annotations

import argparse
import sys
from pathlib import Path


# NFR-01, 02 and 04 to 07 are measured by scripts/perf/ instead.
NFR_IDS = ("03", "08", "09")


def parse_nfr_selection(value: str) -> tuple[str, ...]:
    selection = value.strip()
    if selection == "all":
        return NFR_IDS

    selected = tuple(part.strip() for part in selection.split(","))
    if not selected or any(not item for item in selected):
        raise ValueError("select 'all' or a comma-separated list of NFR IDs from 03, 08, 09")
    if any(item not in NFR_IDS for item in selected):
        raise ValueError("NFR IDs must be zero-padded values from 03, 08, 09")
    if len(set(selected)) != len(selected):
        raise ValueError("an NFR ID cannot be selected more than once")
    return selected


def write_github_outputs(selection: str, output_path: Path) -> None:
    selected = parse_nfr_selection(selection)
    is_all = selection.strip() == "all"
    values = {
        "selected": ",".join(selected),
        "all": str(is_all).lower(),
        "requires_binary": str("03" in selected).lower(),
    }
    values.update({f"nfr_{item}": str(item in selected).lower() for item in NFR_IDS})
    with output_path.open("a", encoding="utf-8") as stream:
        for name, value in values.items():
            stream.write(f"{name}={value}\n")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("selection", help="all or comma-separated NFR IDs from 03, 08, 09")
    parser.add_argument("--github-output", required=True, type=Path, help="GitHub Actions output file")
    args = parser.parse_args()
    try:
        write_github_outputs(args.selection, args.github_output)
    except (OSError, ValueError) as error:
        print(f"invalid NFR selection: {error}", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
