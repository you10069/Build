#!/usr/bin/env python3
"""Patch Mihomo's VLESS share-link parser to support path=/ws?ed=2560.

The patch keeps Mihomo's existing top-level `&ed=` support and adds fallback
parsing of `ed` from the decoded WebSocket path query. The top-level value
wins if both forms are present. The `ed` control parameter is removed from the
actual WebSocket path while all other path query parameters are retained.
"""

from __future__ import annotations

import argparse
import os
import sys
import tempfile
from pathlib import Path

DEFAULT_SOURCE = Path("common/convert/v.go")
START_TOKEN = '\tcase "ws", "httpupgrade":'
END_TOKEN = '\n\tcase "grpc":'
PATCH_MARKER = "// Support Xray-style path=/ws?ed=2560."

OLD_PATH_LINE = '\t\twsOpts["path"] = query.Get("path")\n'
OLD_ED_CONDITION = 'if earlyData := query.Get("ed"); earlyData != "" {'
NEW_ED_CONDITION = 'if earlyData != "" {'

NEW_PATH_BLOCK = '''\t\tpath := query.Get("path")
\t\tearlyData := query.Get("ed")

\t\t// Support Xray-style path=/ws?ed=2560.
\t\t// The top-level &ed= value takes precedence when both forms exist.
\t\tif network == "ws" && path != "" {
\t\t\tif pathURL, err := url.Parse(path); err == nil {
\t\t\t\tpathQuery := pathURL.Query()
\t\t\t\tif pathEarlyData := pathQuery.Get("ed"); pathEarlyData != "" && earlyData == "" {
\t\t\t\t\tearlyData = pathEarlyData
\t\t\t\t}
\t\t\t\tif _, exists := pathQuery["ed"]; exists {
\t\t\t\t\tpathQuery.Del("ed")
\t\t\t\t\tpathURL.RawQuery = pathQuery.Encode()
\t\t\t\t\tpath = pathURL.String()
\t\t\t\t}
\t\t\t}
\t\t}

\t\twsOpts["path"] = path
'''


class PatchError(RuntimeError):
    """Raised when the expected upstream source structure is not found."""


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Add Xray-style WebSocket path early-data parsing to Mihomo."
    )
    parser.add_argument(
        "--file",
        type=Path,
        default=DEFAULT_SOURCE,
        help=f"Mihomo v.go source path (default: {DEFAULT_SOURCE})",
    )
    parser.add_argument(
        "--check",
        action="store_true",
        help="Check whether the patch is applicable/applied without writing files.",
    )
    return parser.parse_args()


def find_ws_block(source: str) -> tuple[int, int, str]:
    start_count = source.count(START_TOKEN)
    if start_count != 1:
        raise PatchError(
            f"expected exactly one {START_TOKEN!r}, found {start_count}; "
            "the upstream parser structure may have changed"
        )

    start = source.index(START_TOKEN)
    end = source.find(END_TOKEN, start)
    if end == -1:
        raise PatchError(
            f"could not find the end of the WebSocket parser block ({END_TOKEN!r}); "
            "the upstream parser structure may have changed"
        )

    return start, end, source[start:end]


def build_patched_source(source: str) -> tuple[str, str]:
    """Return (status, source), where status is 'applied' or 'already-applied'."""
    _, _, block = find_ws_block(source)

    if PATCH_MARKER in block:
        required_fragments = (
            'earlyData := query.Get("ed")',
            'pathQuery.Get("ed")',
            'pathQuery.Del("ed")',
            NEW_ED_CONDITION,
        )
        missing = [fragment for fragment in required_fragments if fragment not in block]
        if missing:
            raise PatchError(
                "the patch marker exists, but the patched block is incomplete; "
                f"missing: {', '.join(missing)}"
            )
        return "already-applied", source

    path_line_count = block.count(OLD_PATH_LINE)
    ed_condition_count = block.count(OLD_ED_CONDITION)
    if path_line_count != 1 or ed_condition_count != 1:
        raise PatchError(
            "expected Mihomo's current WebSocket parser statements were not found "
            f"exactly once (path line: {path_line_count}, ed condition: {ed_condition_count}); "
            "the upstream source may have changed"
        )

    patched_block = block.replace(OLD_PATH_LINE, NEW_PATH_BLOCK, 1)
    patched_block = patched_block.replace(OLD_ED_CONDITION, NEW_ED_CONDITION, 1)

    if OLD_PATH_LINE in patched_block or OLD_ED_CONDITION in patched_block:
        raise PatchError("internal validation failed: original statements remain after patching")

    if patched_block.count(PATCH_MARKER) != 1:
        raise PatchError("internal validation failed: patch marker was not inserted exactly once")

    start, end, _ = find_ws_block(source)
    patched_source = source[:start] + patched_block + source[end:]
    return "applied", patched_source


def atomic_write(path: Path, content: str) -> None:
    """Write content atomically while preserving the existing file mode."""
    stat_result = path.stat()
    temp_name: str | None = None

    try:
        with tempfile.NamedTemporaryFile(
            mode="w",
            encoding="utf-8",
            newline="",
            dir=path.parent,
            prefix=f".{path.name}.",
            suffix=".tmp",
            delete=False,
        ) as temp_file:
            temp_name = temp_file.name
            temp_file.write(content)
            temp_file.flush()
            os.fsync(temp_file.fileno())

        os.chmod(temp_name, stat_result.st_mode)
        os.replace(temp_name, path)
    finally:
        if temp_name is not None and os.path.exists(temp_name):
            os.unlink(temp_name)


def main() -> int:
    args = parse_args()
    source_path: Path = args.file

    if not source_path.is_file():
        print(f"error: source file not found: {source_path}", file=sys.stderr)
        return 2

    try:
        source = source_path.read_text(encoding="utf-8")
        status, patched_source = build_patched_source(source)
    except (OSError, UnicodeError, PatchError) as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 1

    if args.check:
        if status == "already-applied":
            print(f"patch is already applied: {source_path}")
        else:
            print(f"patch is applicable: {source_path}")
        return 0

    if status == "already-applied":
        print(f"patch already applied; skipping: {source_path}")
        return 0

    try:
        atomic_write(source_path, patched_source)
    except OSError as exc:
        print(f"error: failed to write {source_path}: {exc}", file=sys.stderr)
        return 1

    print(f"Mihomo WebSocket path early-data patch applied: {source_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
