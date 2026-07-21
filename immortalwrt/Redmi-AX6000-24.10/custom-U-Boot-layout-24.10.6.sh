#!/usr/bin/env bash
# Restore Xiaomi Redmi Router AX6000 (110 MiB UBI with NMBM-enabled
# custom U-Boot layout) for ImmortalWrt v24.10.6.
#
# Run this script from the root of the ImmortalWrt v24.10.6 source tree.
# It intentionally does NOT modify platform.sh. This layout uses the standard
# sysupgrade-tar + nand_do_upgrade path with UBI volumes
# kernel/rootfs/rootfs_data.

set -euo pipefail

readonly DEVICE_COMPAT='xiaomi,redmi-router-ax6000'
readonly DEVICE_NAME='xiaomi_redmi-router-ax6000'
readonly SOURCE_ROOT="$(pwd -P)"

log() {
	printf '[AX6000 restore] %s\n' "$*"
}

fatal() {
	printf '[AX6000 restore] ERROR: %s\n' "$*" >&2
	exit 1
}

command -v python3 >/dev/null 2>&1 || fatal 'python3 is required.'
command -v sh >/dev/null 2>&1 || fatal 'sh is required.'
command -v sed >/dev/null 2>&1 || fatal 'sed is required.'
command -v grep >/dev/null 2>&1 || fatal 'grep is required.'

required_paths=(
	'include/version.mk'
	'target/linux/mediatek/image/filogic.mk'
	'target/linux/mediatek/dts/mt7986a-xiaomi-redmi-router-ax6000.dtsi'
	'target/linux/mediatek/base-files/lib/preinit/05_set_preinit_iface'
	'target/linux/mediatek/filogic/base-files/etc/board.d/01_leds'
	'target/linux/mediatek/filogic/base-files/etc/board.d/02_network'
	'target/linux/mediatek/filogic/base-files/lib/upgrade/platform.sh'
	'package/boot/uboot-envtools/files/mediatek_filogic'
)

for path in "${required_paths[@]}"; do
	[[ -e "$SOURCE_ROOT/$path" ]] \
		|| fatal "Missing required path: $path. Run this script from the ImmortalWrt source root."
done

if ! grep -Eq '^VERSION_NUMBER:=\$\(if \$\(VERSION_NUMBER\),\$\(VERSION_NUMBER\),24\.10\.6\)$' \
	"$SOURCE_ROOT/include/version.mk"; then
	fatal 'This patch is version-specific and expected ImmortalWrt v24.10.6.'
fi

readonly PLATFORM_FILE='target/linux/mediatek/filogic/base-files/lib/upgrade/platform.sh'

# The restored board must remain on the generic nand_do_upgrade path. Refuse
# to stack this patch on top of an earlier custom platform.sh implementation.
if grep -Eq '^[[:space:]]*xiaomi,redmi-router-ax6000(\|\\|\))$' \
	"$SOURCE_ROOT/$PLATFORM_FILE"; then
	fatal "$DEVICE_COMPAT is already present in platform.sh. Remove that custom upgrade branch before applying this patch."
fi

workdir="$(mktemp -d "${TMPDIR:-/tmp}/ax6000-24.10.6.XXXXXX")"
cleanup() {
	rm -rf "$workdir"
}
trap cleanup EXIT

log 'Preparing patched files with strict anchor and idempotency checks...'

python3 - "$SOURCE_ROOT" "$workdir" <<'PY'
from __future__ import annotations

import re
import shutil
import sys
from pathlib import Path
from typing import NoReturn

source_root = Path(sys.argv[1]).resolve()
staging_root = Path(sys.argv[2]).resolve()

compat = "xiaomi,redmi-router-ax6000"
device_name = "xiaomi_redmi-router-ax6000"

paths = {
    "dts": Path("target/linux/mediatek/dts/mt7986a-xiaomi-redmi-router-ax6000.dts"),
    "filogic": Path("target/linux/mediatek/image/filogic.mk"),
    "preinit": Path("target/linux/mediatek/base-files/lib/preinit/05_set_preinit_iface"),
    "leds": Path("target/linux/mediatek/filogic/base-files/etc/board.d/01_leds"),
    "network": Path("target/linux/mediatek/filogic/base-files/etc/board.d/02_network"),
    "uboot_env": Path("package/boot/uboot-envtools/files/mediatek_filogic"),
}


def fail(message: str) -> NoReturn:
    raise SystemExit(f"[AX6000 restore] ERROR: {message}")


def read_text(relpath: Path) -> str:
    path = source_root / relpath
    try:
        return path.read_text(encoding="utf-8")
    except FileNotFoundError:
        fail(f"Missing source file: {relpath}")


def stage_text(relpath: Path, text: str) -> None:
    destination = staging_root / relpath
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_text(text, encoding="utf-8", newline="\n")


def replace_exact(
    text: str,
    old: str,
    new: str,
    *,
    expected_count: int,
    label: str,
) -> str:
    count = text.count(old)
    if count != expected_count:
        fail(
            f"{label}: expected anchor {expected_count} time(s), found {count}. "
            "The source may not be pristine ImmortalWrt v24.10.6."
        )
    return text.replace(old, new)


def ensure_inserted(
    text: str,
    *,
    inserted: str,
    old_anchor: str,
    new_anchor: str,
    expected_occurrences: int,
    label: str,
) -> str:
    inserted_count = text.count(inserted)
    if inserted_count == expected_occurrences:
        if text.count(new_anchor) != expected_occurrences:
            fail(f"{label}: device entry exists but is not in the expected case block(s).")
        return text
    if inserted_count != 0:
        fail(
            f"{label}: found {inserted_count} existing device entry/entries; "
            f"expected either 0 or {expected_occurrences}."
        )
    return replace_exact(
        text,
        old_anchor,
        new_anchor,
        expected_count=expected_occurrences,
        label=label,
    )


def count_exact_board_lines(text: str, board: str) -> int:
    pattern = re.compile(
        rf"^[ \t]*{re.escape(board)}(?:\|\\|\))$",
        re.MULTILINE,
    )
    return len(pattern.findall(text))


dts_text = """// SPDX-License-Identifier: (GPL-2.0 OR MIT)

/dts-v1/;
#include \"mt7986a-xiaomi-redmi-router-ax6000.dtsi\"

/ {
\tmodel = \"Xiaomi Redmi Router AX6000\";
\tcompatible = \"xiaomi,redmi-router-ax6000\", \"mediatek,mt7986a\";
};

&spi_nand_flash {
\tmediatek,nmbm;
\tmediatek,bmt-max-ratio = <1>;
\tmediatek,bmt-max-reserved-blocks = <64>;
};

&partitions {
\tpartition@580000 {
\t\tlabel = \"crash\";
\t\treg = <0x580000 0x40000>;
\t\tread-only;
\t};

\tpartition@5c0000 {
\t\tlabel = \"crash_log\";
\t\treg = <0x5c0000 0x40000>;
\t\tread-only;
\t};

\t/* ubi partition is the result of squashing
\t * consecutive stock partitions:
\t * - ubi
\t * - ubi1
\t * - overlay
\t */
\tpartition@600000 {
\t\tlabel = \"ubi\";
\t\treg = <0x600000 0x6e00000>;
\t};

\t/* last 12 MiB is reserved for NMBM bad block table */
};
"""

device_block = """define Device/xiaomi_redmi-router-ax6000
  DEVICE_VENDOR := Xiaomi
  DEVICE_MODEL := Redmi Router AX6000
  DEVICE_VARIANT := (custom U-Boot layout)
  DEVICE_DTS := mt7986a-xiaomi-redmi-router-ax6000
  DEVICE_DTS_DIR := ../dts
  DEVICE_PACKAGES := kmod-leds-ws2812b kmod-mt7915e kmod-mt7986-firmware mt7986-wo-firmware
  KERNEL_LOADADDR := 0x48000000
  UBINIZE_OPTS := -E 5
  BLOCKSIZE := 128k
  PAGESIZE := 2048
  IMAGE_SIZE := 112640k
  KERNEL_IN_UBI := 1
  IMAGES += factory.bin
  IMAGE/factory.bin := append-ubi | check-size $$$$(IMAGE_SIZE)
  IMAGE/sysupgrade.bin := sysupgrade-tar | append-metadata
endef
TARGET_DEVICES += xiaomi_redmi-router-ax6000
"""

# 1. DTS: create it, or verify an existing file byte-for-byte.
dts_path = source_root / paths["dts"]
if dts_path.exists():
    current_dts = dts_path.read_text(encoding="utf-8")
    if current_dts != dts_text:
        fail(f"Existing {paths['dts']} differs from the expected v24.10.6 restoration.")
stage_text(paths["dts"], dts_text)

# 2. Image definition: insert immediately before the stock-layout AX6000.
filogic = read_text(paths["filogic"])
definition_marker = "define Device/xiaomi_redmi-router-ax6000\n"
target_marker = "TARGET_DEVICES += xiaomi_redmi-router-ax6000\n"
expected_complete_block = device_block + "\n"

if definition_marker in filogic or target_marker in filogic:
    if filogic.count(definition_marker) != 1 or filogic.count(target_marker) != 1:
        fail("filogic.mk contains a partial or duplicate AX6000 custom-layout definition.")
    if expected_complete_block not in filogic:
        fail("The existing AX6000 custom Device block does not match the expected v24.10.6 definition.")
else:
    stock_anchor = "define Device/xiaomi_redmi-router-ax6000-stock\n"
    filogic = replace_exact(
        filogic,
        stock_anchor,
        expected_complete_block + stock_anchor,
        expected_count=1,
        label="filogic.mk",
    )
stage_text(paths["filogic"], filogic)

# 3. preinit/failsafe interface: AX6000 has lan2/lan3/lan4, so use lan4.
preinit = read_text(paths["preinit"])
preinit_old = (
    "\txiaomi,redmi-router-ax6000-stock|\\\n"
    "\txiaomi,redmi-router-ax6000-ubootmod)\n"
)
preinit_new = (
    "\txiaomi,redmi-router-ax6000|\\\n"
    "\txiaomi,redmi-router-ax6000-stock|\\\n"
    "\txiaomi,redmi-router-ax6000-ubootmod)\n"
)
preinit = ensure_inserted(
    preinit,
    inserted="\txiaomi,redmi-router-ax6000|\\\n",
    old_anchor=preinit_old,
    new_anchor=preinit_new,
    expected_occurrences=1,
    label="05_set_preinit_iface",
)
stage_text(paths["preinit"], preinit)

# 4. RGB WAN LED definition.
leds = read_text(paths["leds"])
leds_old = (
    "xiaomi,redmi-router-ax6000-stock|\\\n"
    "xiaomi,redmi-router-ax6000-ubootmod)\n"
)
leds_new = (
    "xiaomi,redmi-router-ax6000|\\\n"
    "xiaomi,redmi-router-ax6000-stock|\\\n"
    "xiaomi,redmi-router-ax6000-ubootmod)\n"
)
leds = ensure_inserted(
    leds,
    inserted="xiaomi,redmi-router-ax6000|\\\n",
    old_anchor=leds_old,
    new_anchor=leds_new,
    expected_occurrences=1,
    label="01_leds",
)
stage_text(paths["leds"], leds)

# 5. Network topology and Bdata WAN MAC: this AX6000 anchor occurs twice.
network = read_text(paths["network"])
network_old = (
    "\txiaomi,redmi-router-ax6000-stock|\\\n"
    "\txiaomi,redmi-router-ax6000-ubootmod)\n"
)
network_new = (
    "\txiaomi,redmi-router-ax6000|\\\n"
    "\txiaomi,redmi-router-ax6000-stock|\\\n"
    "\txiaomi,redmi-router-ax6000-ubootmod)\n"
)
network = ensure_inserted(
    network,
    inserted="\txiaomi,redmi-router-ax6000|\\\n",
    old_anchor=network_old,
    new_anchor=network_new,
    expected_occurrences=2,
    label="02_network",
)
stage_text(paths["network"], network)

# 6. Custom/stock-style U-Boot environment remains in raw MTD partitions.
uboot_env = read_text(paths["uboot_env"])
env_old = (
    "xiaomi,mi-router-ax3000t|\\\n"
    "xiaomi,mi-router-wr30u-stock|\\\n"
    "xiaomi,redmi-router-ax6000-stock)\n"
)
env_new = (
    "xiaomi,mi-router-ax3000t|\\\n"
    "xiaomi,mi-router-wr30u-stock|\\\n"
    "xiaomi,redmi-router-ax6000|\\\n"
    "xiaomi,redmi-router-ax6000-stock)\n"
)
uboot_env = ensure_inserted(
    uboot_env,
    inserted="xiaomi,redmi-router-ax6000|\\\n",
    old_anchor=env_old,
    new_anchor=env_new,
    expected_occurrences=1,
    label="mediatek_filogic uboot-envtools",
)
stage_text(paths["uboot_env"], uboot_env)

# Global staged-content validation.
staged = {key: (staging_root / rel).read_text(encoding="utf-8") for key, rel in paths.items()}

checks = [
    (staged["dts"].count('compatible = "xiaomi,redmi-router-ax6000"'), 1, "DTS compatible"),
    (staged["dts"].count("mediatek,nmbm;"), 1, "DTS NMBM flag"),
    (staged["dts"].count("reg = <0x600000 0x6e00000>;"), 1, "DTS 110 MiB UBI partition"),
    (staged["dts"].count("reg = <0x580000 0x40000>;"), 1, "DTS crash partition"),
    (staged["dts"].count("reg = <0x5c0000 0x40000>;"), 1, "DTS crash_log partition"),
    (staged["filogic"].count(definition_marker), 1, "Device definition"),
    (staged["filogic"].count(target_marker), 1, "TARGET_DEVICES entry"),
    (count_exact_board_lines(staged["preinit"], compat), 1, "preinit board entry"),
    (count_exact_board_lines(staged["leds"], compat), 1, "LED board entry"),
    (count_exact_board_lines(staged["network"], compat), 2, "network board entries"),
    (count_exact_board_lines(staged["uboot_env"], compat), 1, "U-Boot environment entry"),
]
for actual, expected, label in checks:
    if actual != expected:
        fail(f"Validation failed for {label}: expected {expected}, found {actual}.")

required_fragments = [
    "DEVICE_PACKAGES := kmod-leds-ws2812b kmod-mt7915e kmod-mt7986-firmware mt7986-wo-firmware",
    "KERNEL_LOADADDR := 0x48000000",
    "IMAGE_SIZE := 112640k",
    "KERNEL_IN_UBI := 1",
    "IMAGES += factory.bin",
    "IMAGE/factory.bin := append-ubi | check-size $$$$(IMAGE_SIZE)",
    "IMAGE/sysupgrade.bin := sysupgrade-tar | append-metadata",
]
for fragment in required_fragments:
    if device_block.count(fragment) != 1 or staged["filogic"].count(fragment) < 1:
        fail(f"Device definition is missing required fragment: {fragment}")

for forbidden in (
    "UBOOTENV_IN_UBI := 1",
    "IMAGES := sysupgrade.itb",
    "IMAGE/sysupgrade.itb",
    "fit_do_upgrade",
):
    if forbidden in device_block:
        fail(f"Forbidden ubootmod behavior leaked into the custom-layout Device block: {forbidden}")

# Verify the board entries landed in the intended runtime branches.
if preinit_new not in staged["preinit"] or "\t\tifname=lan4\n" not in staged["preinit"]:
    fail("The AX6000 custom board was not placed in the preinit lan4 branch.")
if leds_new not in staged["leds"] or '"rgb:network"' not in staged["leds"]:
    fail("The AX6000 custom board was not placed in the RGB WAN LED branch.")
if staged["network"].count(network_new) != 2:
    fail("The AX6000 custom board was not placed in both network and MAC branches.")
if env_new not in staged["uboot_env"]:
    fail("The AX6000 custom board was not placed in the raw-MTD U-Boot environment branch.")

# Preserve source permissions in staging for existing files.
for relpath in paths.values():
    source = source_root / relpath
    staged_path = staging_root / relpath
    if source.exists():
        shutil.copymode(source, staged_path)
PY

shell_files=(
	'target/linux/mediatek/base-files/lib/preinit/05_set_preinit_iface'
	'target/linux/mediatek/filogic/base-files/etc/board.d/01_leds'
	'target/linux/mediatek/filogic/base-files/etc/board.d/02_network'
	'package/boot/uboot-envtools/files/mediatek_filogic'
)

log 'Checking generated shell syntax before changing the source tree...'
for file in "${shell_files[@]}"; do
	sh -n "$workdir/$file" || fatal "Shell syntax check failed: $file"
done

log 'Committing the validated changes...'
python3 - "$SOURCE_ROOT" "$workdir" <<'PY'
from __future__ import annotations

import os
import re
import shutil
import sys
from pathlib import Path

source_root = Path(sys.argv[1]).resolve()
staging_root = Path(sys.argv[2]).resolve()

files = [
    Path("target/linux/mediatek/dts/mt7986a-xiaomi-redmi-router-ax6000.dts"),
    Path("target/linux/mediatek/image/filogic.mk"),
    Path("target/linux/mediatek/base-files/lib/preinit/05_set_preinit_iface"),
    Path("target/linux/mediatek/filogic/base-files/etc/board.d/01_leds"),
    Path("target/linux/mediatek/filogic/base-files/etc/board.d/02_network"),
    Path("package/boot/uboot-envtools/files/mediatek_filogic"),
]

for relpath in files:
    source = staging_root / relpath
    destination = source_root / relpath
    destination.parent.mkdir(parents=True, exist_ok=True)

    if destination.exists() and destination.read_bytes() == source.read_bytes():
        continue

    mode = destination.stat().st_mode if destination.exists() else 0o100644
    temporary = destination.with_name(destination.name + ".ax6000-restore.tmp")
    shutil.copyfile(source, temporary)
    os.chmod(temporary, mode & 0o7777)
    os.replace(temporary, destination)
PY

log 'Running post-apply validation...'

readonly DTS_FILE='target/linux/mediatek/dts/mt7986a-xiaomi-redmi-router-ax6000.dts'
readonly FILOGIC_MK='target/linux/mediatek/image/filogic.mk'
readonly PREINIT_FILE='target/linux/mediatek/base-files/lib/preinit/05_set_preinit_iface'
readonly LED_FILE='target/linux/mediatek/filogic/base-files/etc/board.d/01_leds'
readonly NETWORK_FILE='target/linux/mediatek/filogic/base-files/etc/board.d/02_network'
readonly ENV_FILE='package/boot/uboot-envtools/files/mediatek_filogic'

count_board_entries() {
	local file="$1"
	grep -Ec '^[[:space:]]*xiaomi,redmi-router-ax6000(\|\\|\))$' "$file" || true
}

[[ -f "$DTS_FILE" ]] || fatal "DTS was not created: $DTS_FILE"
[[ "$(grep -Fxc "define Device/$DEVICE_NAME" "$FILOGIC_MK")" -eq 1 ]] || fatal 'Device definition count is not 1.'
[[ "$(grep -Fxc "TARGET_DEVICES += $DEVICE_NAME" "$FILOGIC_MK")" -eq 1 ]] || fatal 'TARGET_DEVICES entry count is not 1.'
[[ "$(count_board_entries "$PREINIT_FILE")" -eq 1 ]] || fatal 'preinit entry count is not 1.'
[[ "$(count_board_entries "$LED_FILE")" -eq 1 ]] || fatal 'LED entry count is not 1.'
[[ "$(count_board_entries "$NETWORK_FILE")" -eq 2 ]] || fatal 'network entry count is not 2.'
[[ "$(count_board_entries "$ENV_FILE")" -eq 1 ]] || fatal 'U-Boot environment entry count is not 1.'
! grep -Eq '^[[:space:]]*xiaomi,redmi-router-ax6000(\|\\|\))$' "$PLATFORM_FILE" || fatal 'platform.sh was unexpectedly modified for this board.'

grep -Fq 'reg = <0x600000 0x6e00000>;' "$DTS_FILE" || fatal 'DTS 110 MiB UBI partition is missing.'
grep -Fq 'IMAGE_SIZE := 112640k' "$FILOGIC_MK" || fatal 'IMAGE_SIZE 112640k is missing.'
grep -Fq 'KERNEL_IN_UBI := 1' "$FILOGIC_MK" || fatal 'KERNEL_IN_UBI is missing.'
grep -Fq 'IMAGE/factory.bin := append-ubi | check-size $$$$(IMAGE_SIZE)' "$FILOGIC_MK" || fatal 'factory.bin build rule is missing.'
grep -Fq 'IMAGE/sysupgrade.bin := sysupgrade-tar | append-metadata' "$FILOGIC_MK" || fatal 'sysupgrade-tar build rule is missing.'

for file in "${shell_files[@]}"; do
	sh -n "$file" || fatal "Post-apply shell syntax check failed: $file"
done

if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
	git diff --check || fatal 'git diff --check reported whitespace errors.'
fi

log 'Restoration completed successfully.'
printf '\nRestored Device definition:\n\n'
sed -n "/^define Device\/$DEVICE_NAME$/,/^endef$/p" "$FILOGIC_MK"
printf '\nTARGET_DEVICES entry:\n'
grep -Fx "TARGET_DEVICES += $DEVICE_NAME" "$FILOGIC_MK"
printf '\nRuntime board-name occurrence counts:\n'
printf '  preinit:       %s\n' "$(count_board_entries "$PREINIT_FILE")"
printf '  LED setup:     %s\n' "$(count_board_entries "$LED_FILE")"
printf '  network/MAC:   %s\n' "$(count_board_entries "$NETWORK_FILE")"
printf '  U-Boot env:    %s\n' "$(count_board_entries "$ENV_FILE")"
printf '  platform.sh:   %s (must remain 0)\n' "$(count_board_entries "$PLATFORM_FILE")"
