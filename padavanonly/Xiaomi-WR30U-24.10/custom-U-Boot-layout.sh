#!/usr/bin/env bash
set -euo pipefail

ROOT="$(pwd)"
PROFILE="xiaomi_mi-router-wr30u-112m-nmbm"
COMPAT="xiaomi,mi-router-wr30u-112m-nmbm"

DTS="$ROOT/target/linux/mediatek/dts/mt7981b-xiaomi-mi-router-wr30u-112m-nmbm.dts"
DTSI="$ROOT/target/linux/mediatek/dts/mt7981b-xiaomi-mi-router-wr30u.dtsi"
IMAGE_MK="$ROOT/target/linux/mediatek/image/filogic.mk"
LEDS="$ROOT/target/linux/mediatek/filogic/base-files/etc/board.d/01_leds"
NETWORK="$ROOT/target/linux/mediatek/filogic/base-files/etc/board.d/02_network"
UBOOT_ENV="$ROOT/package/boot/uboot-envtools/files/mediatek_filogic"
PREINIT="$ROOT/target/linux/mediatek/base-files/lib/preinit/05_set_preinit_iface"

fail() {
  echo "ERROR: $*" >&2
  exit 1
}

for file in "$DTSI" "$IMAGE_MK" "$LEDS" "$NETWORK" "$UBOOT_ENV" "$PREINIT"; do
  [ -f "$file" ] || fail "Missing source file: $file"
done

grep -q '^define Device/xiaomi_mi-router-wr30u-stock$' "$IMAGE_MK" \
  || fail "WR30U stock profile marker not found; this script targets padavanonly openwrt-24.10-6.6."

grep -q '^define Device/xiaomi_mi-router-wr30u-ubootmod$' "$IMAGE_MK" \
  || fail "WR30U ubootmod profile marker not found; source layout is unexpected."

cat > "$DTS" <<'DTS_EOF'
// SPDX-License-Identifier: GPL-2.0-or-later OR MIT

/dts-v1/;
#include "mt7981b-xiaomi-mi-router-wr30u.dtsi"

/ {
	model = "Xiaomi Mi Router WR30U (112M UBI with NMBM-Enabled custom U-Boot layout)";
	compatible = "xiaomi,mi-router-wr30u-112m-nmbm", "mediatek,mt7981";
};

&spi_nand {
	mediatek,nmbm;
	mediatek,bmt-max-ratio = <1>;
	mediatek,bmt-max-reserved-blocks = <64>;
};

&partitions {
	partition@600000 {
		label = "ubi";
		reg = <0x600000 0x7000000>;
	};
};
DTS_EOF

python3 - "$IMAGE_MK" "$LEDS" "$NETWORK" "$UBOOT_ENV" "$PREINIT" <<'PY'
from pathlib import Path
import sys

image_mk, leds, network, uboot_env, preinit = map(Path, sys.argv[1:])

profile = '''define Device/xiaomi_mi-router-wr30u-112m-nmbm
  DEVICE_VENDOR := Xiaomi
  DEVICE_MODEL := Mi Router WR30U
  DEVICE_VARIANT := (112M UBI with NMBM-Enabled custom U-Boot layout)
  DEVICE_DTS := mt7981b-xiaomi-mi-router-wr30u-112m-nmbm
  DEVICE_DTS_DIR := ../dts
  UBINIZE_OPTS := -E 5
  BLOCKSIZE := 128k
  PAGESIZE := 2048
  DEVICE_PACKAGES := kmod-mt7915e kmod-mt7981-firmware mt7981-wo-firmware
ifneq ($(CONFIG_TARGET_ROOTFS_INITRAMFS),)
  ARTIFACTS := initramfs-factory.ubi
  ARTIFACT/initramfs-factory.ubi := append-image-stage initramfs-kernel.bin | ubinize-kernel
endif
  IMAGE/sysupgrade.bin := sysupgrade-tar | append-metadata
endef
TARGET_DEVICES += xiaomi_mi-router-wr30u-112m-nmbm

'''

text = image_mk.read_text()
if "define Device/xiaomi_mi-router-wr30u-112m-nmbm\n" not in text:
    marker = "define Device/xiaomi_mi-router-wr30u-stock\n"
    if marker not in text:
        raise SystemExit("WR30U stock profile marker not found in filogic.mk")
    text = text.replace(marker, profile + marker, 1)
    image_mk.write_text(text)


def insert_compat_before_stock(path: Path, minimum: int) -> None:
    lines = path.read_text().splitlines(keepends=True)
    result = []
    stock_count = 0
    custom_line = "xiaomi,mi-router-wr30u-112m-nmbm|\\"

    for line in lines:
        stripped = line.strip()
        if stripped.startswith("xiaomi,mi-router-wr30u-stock") and (
            stripped.endswith("|\\") or stripped.endswith(")")
        ):
            stock_count += 1
            previous = result[-1].strip() if result else ""
            if previous != custom_line:
                indent = line[: len(line) - len(line.lstrip())]
                result.append(indent + custom_line + "\n")
        result.append(line)

    if stock_count < minimum:
        raise SystemExit(
            f"Expected at least {minimum} WR30U stock markers in {path}, found {stock_count}"
        )

    path.write_text("".join(result))


# Historical custom profile integration points.
insert_compat_before_stock(leds, 1)
insert_compat_before_stock(network, 2)
insert_compat_before_stock(uboot_env, 1)

# This newer padavanonly branch explicitly maps WR30U to lan4 during preinit.
# Add the custom compatible so failsafe/preinit does not fall back to lan1.
insert_compat_before_stock(preinit, 1)
PY

grep -q '^define Device/xiaomi_mi-router-wr30u-112m-nmbm$' "$IMAGE_MK"
grep -q 'compatible = "xiaomi,mi-router-wr30u-112m-nmbm"' "$DTS"
grep -q 'reg = <0x600000 0x7000000>;' "$DTS"
grep -q '^[[:space:]]*xiaomi,mi-router-wr30u-112m-nmbm|\\$' "$LEDS"
[ "$(grep -c '^[[:space:]]*xiaomi,mi-router-wr30u-112m-nmbm|\\$' "$NETWORK")" -ge 2 ]
grep -q '^[[:space:]]*xiaomi,mi-router-wr30u-112m-nmbm|\\$' "$UBOOT_ENV"
grep -q '^[[:space:]]*xiaomi,mi-router-wr30u-112m-nmbm|\\$' "$PREINIT"

if command -v git >/dev/null 2>&1 && git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  git diff --check
fi

echo
printf '%s\n' "WR30U 112M NMBM custom U-Boot layout added for padavanonly openwrt-24.10-6.6."
printf '%s\n' "Select: CONFIG_TARGET_DEVICE_mediatek_filogic_DEVICE_xiaomi_mi-router-wr30u-112m-nmbm=y"
printf '%s\n' "Optional initramfs factory artifact: CONFIG_TARGET_ROOTFS_INITRAMFS=y"
echo
sed -n "/^define Device\/${PROFILE}$/,/^TARGET_DEVICES += ${PROFILE}$/p" "$IMAGE_MK"
