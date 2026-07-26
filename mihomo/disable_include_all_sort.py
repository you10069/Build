#!/usr/bin/env python3
"""
Disable Mihomo include-all name sorting.

This script removes only these two calls from config/config.go:

    slices.Sort(AllProxies)
    slices.Sort(AllProviders)

It intentionally keeps the slices import because current Mihomo versions also
use slices.ContainsFunc elsewhere in config/config.go.

Behavior:
- Applies the patch once.
- Exits successfully if the patch is already applied.
- Fails safely if only one expected line exists or the upstream code structure
  no longer matches.
- Supports a custom target file and check-only mode.
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path


DEFAULT_TARGET = Path("config/config.go")

SORT_ALL_PROXIES = "slices.Sort(AllProxies)"
SORT_ALL_PROVIDERS = "slices.Sort(AllProviders)"

EXPECTED_BLOCKS = (
    "\tslices.Sort(AllProxies)\n\tslices.Sort(AllProviders)\n",
    "\tslices.Sort(AllProxies)\r\n\tslices.Sort(AllProviders)\r\n",
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Disable Mihomo include-all proxy/provider name sorting."
    )
    parser.add_argument(
        "--file",
        type=Path,
        default=DEFAULT_TARGET,
        help=f"Path to config.go (default: {DEFAULT_TARGET})",
    )
    parser.add_argument(
        "--check",
        action="store_true",
        help="Check whether the patch can be applied without modifying the file.",
    )
    return parser.parse_args()


def fail(message: str) -> int:
    print(f"ERROR: {message}", file=sys.stderr)
    return 1


def main() -> int:
    args = parse_args()
    target: Path = args.file

    if not target.is_file():
        return fail(f"target file not found: {target}")

    try:
        source = target.read_text(encoding="utf-8")
    except OSError as exc:
        return fail(f"unable to read {target}: {exc}")

    has_proxy_sort = SORT_ALL_PROXIES in source
    has_provider_sort = SORT_ALL_PROVIDERS in source

    # Already patched: neither sorting call remains.
    if not has_proxy_sort and not has_provider_sort:
        print(f"Patch already applied: {target}")
        return 0

    # Partial or unexpected upstream change: do not modify anything.
    if has_proxy_sort != has_provider_sort:
        return fail(
            "only one expected sorting call was found; "
            "upstream code may have changed, so no modification was made"
        )

    matched_block = next((block for block in EXPECTED_BLOCKS if block in source), None)
    if matched_block is None:
        return fail(
            "both sorting calls exist, but the expected consecutive code block "
            "was not found; upstream code may have changed, so no modification "
            "was made"
        )

    if args.check:
        print(f"Patch can be applied: {target}")
        return 0

    patched = source.replace(matched_block, "", 1)

    # Verify that only the intended calls were removed.
    if SORT_ALL_PROXIES in patched or SORT_ALL_PROVIDERS in patched:
        return fail(
            "sorting calls still remain after replacement; no file was written"
        )

    # Do not remove the slices import. Mihomo currently uses slices.ContainsFunc
    # elsewhere in this file.
    try:
        target.write_text(patched, encoding="utf-8", newline="")
    except OSError as exc:
        return fail(f"unable to write {target}: {exc}")

    print(f"Disabled include-all name sorting in: {target}")
    print("Kept the slices import for other slices usages such as ContainsFunc.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
