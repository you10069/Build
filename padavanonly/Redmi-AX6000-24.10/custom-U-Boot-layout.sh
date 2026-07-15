#!/usr/bin/env bash
set -euo pipefail

ROOT="$(pwd)"
DTS="$ROOT/target/linux/mediatek/dts/mt7986a-xiaomi-redmi-router-ax6000.dts"
IMAGE_MK="$ROOT/target/linux/mediatek/image/filogic.mk"
LEDS="$ROOT/target/linux/mediatek/filogic/base-files/etc/board.d/01_leds"
NETWORK="$ROOT/target/linux/mediatek/filogic/base-files/etc/board.d/02_network"
UBOOT_ENV="$ROOT/package/boot/uboot-envtools/files/mediatek_filogic"

for file in "$IMAGE_MK" "$LEDS" "$NETWORK" "$UBOOT_ENV"; do
  [ -f "$file" ] || { echo "Missing source file: $file" >&2; exit 1; }
done

cat > "$DTS" <<'DTS_EOF'
// SPDX-License-Identifier: (GPL-2.0 OR MIT)

/dts-v1/;
#include "mt7986a-xiaomi-redmi-router-ax6000.dtsi"

/ {
	model = "Xiaomi Redmi Router AX6000 (custom U-Boot layout)";
	compatible = "xiaomi,redmi-router-ax6000", "mediatek,mt7986a";
};

&spi_nand_flash {
	mediatek,nmbm;
	mediatek,bmt-max-ratio = <1>;
	mediatek,bmt-max-reserved-blocks = <64>;
};

&partitions {
	partition@580000 {
		label = "crash";
		reg = <0x580000 0x40000>;
		read-only;
	};

	partition@5c0000 {
		label = "crash_log";
		reg = <0x5c0000 0x40000>;
		read-only;
	};

	partition@600000 {
		label = "ubi";
		reg = <0x600000 0x6e00000>;
	};
};
DTS_EOF

python3 - "$IMAGE_MK" "$LEDS" "$NETWORK" "$UBOOT_ENV" <<'PY'
from pathlib import Path
import sys

image_mk, leds, network, uboot_env = map(Path, sys.argv[1:])

profile = '''define Device/xiaomi_redmi-router-ax6000
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

'''

text = image_mk.read_text()
if "define Device/xiaomi_redmi-router-ax6000\n" not in text:
    marker = "define Device/xiaomi_redmi-router-ax6000-stock\n"
    if marker not in text:
        raise SystemExit("AX6000 stock profile marker not found in filogic.mk")
    text = text.replace(marker, profile + marker, 1)
    image_mk.write_text(text)

def insert_custom_before_stock(path: Path, minimum: int):
    lines = path.read_text().splitlines(keepends=True)
    result = []
    stock_count = 0
    for line in lines:
        stripped = line.strip()
        if stripped.startswith("xiaomi,redmi-router-ax6000-stock") and (stripped.endswith("|\\") or stripped.endswith(")")):
            stock_count += 1
            previous = result[-1].strip() if result else ""
            if previous != "xiaomi,redmi-router-ax6000|\\":
                indent = line[: len(line) - len(line.lstrip())]
                result.append(indent + "xiaomi,redmi-router-ax6000|\\\n")
        result.append(line)
    if stock_count < minimum:
        raise SystemExit(f"Expected at least {minimum} AX6000 stock markers in {path}, found {stock_count}")
    path.write_text("".join(result))

insert_custom_before_stock(leds, 1)
insert_custom_before_stock(network, 2)
insert_custom_before_stock(uboot_env, 1)
PY

grep -q '^define Device/xiaomi_redmi-router-ax6000$' "$IMAGE_MK"
grep -q 'compatible = "xiaomi,redmi-router-ax6000"' "$DTS"
[ "$(grep -c '^[[:space:]]*xiaomi,redmi-router-ax6000|\\$' "$NETWORK")" -ge 2 ]
grep -q '^[[:space:]]*xiaomi,redmi-router-ax6000|\\$' "$LEDS"
grep -q '^[[:space:]]*xiaomi,redmi-router-ax6000|\\$' "$UBOOT_ENV"

echo "AX6000 custom U-Boot layout added for padavanonly openwrt-24.10-6.6."
echo 'Select: CONFIG_TARGET_DEVICE_mediatek_filogic_DEVICE_xiaomi_redmi-router-ax6000=y'
