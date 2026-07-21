#!/usr/bin/env bash
set -euo pipefail

PROFILE="xiaomi_mi-router-wr30u-112m-nmbm"
COMPAT="xiaomi,mi-router-wr30u-112m-nmbm"

fail() {
  echo "ERROR: $*" >&2
  exit 1
}

[ -f target/linux/mediatek/image/filogic.mk ] \
  || fail "请在 ImmortalWrt v24.10.6 源码根目录运行此脚本。"

python3 - <<'PY'
from pathlib import Path
import re

PROFILE = "xiaomi_mi-router-wr30u-112m-nmbm"
COMPAT = "xiaomi,mi-router-wr30u-112m-nmbm"

DTS = Path("target/linux/mediatek/dts/mt7981b-xiaomi-mi-router-wr30u-112m-nmbm.dts")
IMAGE = Path("target/linux/mediatek/image/filogic.mk")
LEDS = Path("target/linux/mediatek/filogic/base-files/etc/board.d/01_leds")
NETWORK = Path("target/linux/mediatek/filogic/base-files/etc/board.d/02_network")
ENVTOOLS = Path("package/boot/uboot-envtools/files/mediatek_filogic")
PREINIT = Path("target/linux/mediatek/base-files/lib/preinit/05_set_preinit_iface")

required = [IMAGE, LEDS, NETWORK, ENVTOOLS, PREINIT]
for path in required:
    if not path.is_file():
        raise SystemExit(f"ERROR: 缺少源码文件：{path}")

dts_text = '''// SPDX-License-Identifier: GPL-2.0-or-later OR MIT

/dts-v1/;
#include "mt7981b-xiaomi-mi-router-wr30u.dtsi"

/ {
\tmodel = "Xiaomi Mi Router WR30U (112M UBI with NMBM-Enabled layout)";
\tcompatible = "xiaomi,mi-router-wr30u-112m-nmbm", "mediatek,mt7981";
};

&spi_nand {
\tmediatek,nmbm;
\tmediatek,bmt-max-ratio = <1>;
\tmediatek,bmt-max-reserved-blocks = <64>;
};

&partitions {
\tpartition@600000 {
\t\tlabel = "ubi";
\t\treg = <0x600000 0x7000000>;
\t};
};
'''

profile_text = '''define Device/xiaomi_mi-router-wr30u-112m-nmbm
  DEVICE_VENDOR := Xiaomi
  DEVICE_MODEL := Mi Router WR30U
  DEVICE_VARIANT := (112M UBI with NMBM-Enabled custom U-Boot layout)
  DEVICE_DTS := mt7981b-xiaomi-mi-router-wr30u-112m-nmbm
  DEVICE_DTS_DIR := ../dts
  UBINIZE_OPTS := -E 5
  BLOCKSIZE := 128k
  PAGESIZE := 2048
  IMAGE_SIZE := 114688k
  KERNEL_IN_UBI := 1
  DEVICE_PACKAGES := kmod-mt7915e kmod-mt7981-firmware mt7981-wo-firmware
ifeq ($(IB),)
ifneq ($(CONFIG_TARGET_ROOTFS_INITRAMFS),)
  ARTIFACTS := initramfs-factory.ubi
  ARTIFACT/initramfs-factory.ubi := append-image-stage initramfs-kernel.bin | ubinize-kernel
endif
endif
  IMAGES += factory.bin
  IMAGE/factory.bin := append-ubi | check-size $$$$(IMAGE_SIZE)
  IMAGE/sysupgrade.bin := sysupgrade-tar | append-metadata
endef
TARGET_DEVICES += xiaomi_mi-router-wr30u-112m-nmbm
'''

# 1. DTS: exact final content.
if DTS.exists() and DTS.read_text() != dts_text:
    raise SystemExit(f"ERROR: {DTS} 已存在但内容不同，请使用干净的 v24.10.6 源码。")
DTS.write_text(dts_text)

# 2. Image profile: replace any older/incomplete restored profile, or insert before stock.
image = IMAGE.read_text()
stock_anchor = "define Device/xiaomi_mi-router-wr30u-stock\n"
if image.count(stock_anchor) != 1:
    raise SystemExit("ERROR: 无法唯一定位 WR30U stock profile；源码版本可能不匹配 v24.10.6。")

pattern = re.compile(
    r"define Device/xiaomi_mi-router-wr30u-112m-nmbm\n.*?"
    r"TARGET_DEVICES \+= xiaomi_mi-router-wr30u-112m-nmbm\n\n?",
    re.S,
)
if pattern.search(image):
    image = pattern.sub(profile_text + "\n", image, count=1)
else:
    image = image.replace(stock_anchor, profile_text + "\n" + stock_anchor, 1)
IMAGE.write_text(image)

# Helper: insert COMPAT directly before a unique/known WR30U stock line.
def add_compat(path: Path, expected_occurrences: int):
    text = path.read_text()
    pattern = re.compile(r"^(?P<indent>[ \t]*)xiaomi,mi-router-wr30u-stock\|\\$", re.M)
    present_pattern = re.compile(
        rf"^[ \t]*{re.escape(COMPAT)}\|\\$", re.M
    )
    present_count = len(present_pattern.findall(text))
    if present_count == expected_occurrences:
        return
    if present_count != 0:
        raise SystemExit(f"ERROR: {path} 中 custom compatible 出现次数异常。")
    matches = list(pattern.finditer(text))
    if len(matches) != expected_occurrences:
        raise SystemExit(
            f"ERROR: {path} 中 WR30U stock 锚点数量为 {len(matches)}，"
            f"预期 {expected_occurrences}。"
        )
    text = pattern.sub(
        lambda m: f"{m.group('indent')}{COMPAT}|\\\n{m.group(0)}",
        text,
    )
    path.write_text(text)

# 3–6. Board integration.
add_compat(LEDS, 1)
add_compat(NETWORK, 2)
add_compat(ENVTOOLS, 1)
add_compat(PREINIT, 1)

# Final validation.
checks = {
    DTS: 1,
    IMAGE: 2,      # define + TARGET_DEVICES
    LEDS: 1,
    NETWORK: 2,
    ENVTOOLS: 1,
    PREINIT: 1,
}
for path, expected in checks.items():
    count = path.read_text().count(COMPAT if path != IMAGE else PROFILE)
    if count != expected:
        raise SystemExit(
            f"ERROR: {path} 验证失败：匹配 {count} 次，预期 {expected} 次。"
        )

# Validate all required final image properties.
final_image = IMAGE.read_text()
required_profile_lines = [
    "IMAGE_SIZE := 114688k",
    "KERNEL_IN_UBI := 1",
    "DEVICE_PACKAGES := kmod-mt7915e kmod-mt7981-firmware mt7981-wo-firmware",
    "IMAGES += factory.bin",
    "IMAGE/factory.bin := append-ubi | check-size $$$$(IMAGE_SIZE)",
    "IMAGE/sysupgrade.bin := sysupgrade-tar | append-metadata",
]
for line in required_profile_lines:
    if line not in final_image:
        raise SystemExit(f"ERROR: profile 缺少：{line}")

print("WR30U 112M NMBM custom layout 已完整写入 ImmortalWrt v24.10.6。")
PY

if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  git diff --check
fi

echo
echo "最终 WR30U custom profile："
sed -n "/^define Device\/${PROFILE}$/,/^TARGET_DEVICES += ${PROFILE}$/p" \
  target/linux/mediatek/image/filogic.mk
