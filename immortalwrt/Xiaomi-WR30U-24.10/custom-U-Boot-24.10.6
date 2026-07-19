#!/usr/bin/env bash
set -euo pipefail

PROFILE="xiaomi_mi-router-wr30u-112m-nmbm"
COMPAT="xiaomi,mi-router-wr30u-112m-nmbm"
EXPECTED_COMMIT="cf234f8de6d5a7a3fa38fa0f7a936a0d8b15856c"

fail() {
  echo "ERROR: $*" >&2
  exit 1
}

[ -f target/linux/mediatek/image/filogic.mk ] \
  || fail "请在 ImmortalWrt v24.10.6 源码根目录运行此脚本。"

# GitHub Actions 中建议严格固定到 24.10.6 对应提交，避免浮动分支变化后误套补丁。
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  current_commit="$(git rev-parse HEAD)"
  [ "$current_commit" = "$EXPECTED_COMMIT" ] \
    || fail "当前提交为 $current_commit，不是 ImmortalWrt v24.10.6 的 $EXPECTED_COMMIT。"
fi

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
PLATFORM = Path("target/linux/mediatek/filogic/base-files/lib/upgrade/platform.sh")

required = [IMAGE, LEDS, NETWORK, ENVTOOLS, PREINIT, PLATFORM]
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

# 保持官方历史 112M NMBM profile 的镜像语义：
# - 生成 sysupgrade tar；
# - 可选 initramfs-factory.ubi；
# - 不额外生成通用 append-ubi factory.bin，因为它会创建名为 kernel 的 UBI 卷，
#   与该 custom U-Boot 使用 fit 卷的历史升级语义不一致。
profile_text = '''define Device/xiaomi_mi-router-wr30u-112m-nmbm
  DEVICE_VENDOR := Xiaomi
  DEVICE_MODEL := Mi Router WR30U
  DEVICE_VARIANT := (112M UBI with NMBM-Enabled custom U-Boot layout)
  DEVICE_DTS := mt7981b-xiaomi-mi-router-wr30u-112m-nmbm
  DEVICE_DTS_DIR := ../dts
  UBINIZE_OPTS := -E 5
  BLOCKSIZE := 128k
  PAGESIZE := 2048
  DEVICE_PACKAGES := kmod-mt7915e kmod-mt7981-firmware mt7981-wo-firmware
ifeq ($(IB),)
ifneq ($(CONFIG_TARGET_ROOTFS_INITRAMFS),)
  ARTIFACTS := initramfs-factory.ubi
  ARTIFACT/initramfs-factory.ubi := append-image-stage initramfs-kernel.bin | ubinize-kernel
endif
endif
  IMAGE/sysupgrade.bin := sysupgrade-tar | append-metadata
endef
TARGET_DEVICES += xiaomi_mi-router-wr30u-112m-nmbm
'''

platform_case = '''\txiaomi,mi-router-wr30u-112m-nmbm)
\t\tCI_KERNPART="fit"
\t\tnand_do_upgrade "$1"
\t\t;;
'''

# 1. DTS：目标内容必须唯一、确定。
if DTS.exists() and DTS.read_text() != dts_text:
    raise SystemExit(f"ERROR: {DTS} 已存在但内容不同，请使用干净的 v24.10.6 源码。")
DTS.write_text(dts_text)

# 2. Image profile：替换旧的/不完整的恢复定义，或插入 stock profile 之前。
image = IMAGE.read_text()
stock_anchor = "define Device/xiaomi_mi-router-wr30u-stock\n"
if image.count(stock_anchor) != 1:
    raise SystemExit("ERROR: 无法唯一定位 WR30U stock profile；源码版本不匹配 v24.10.6。")

profile_pattern = re.compile(
    r"define Device/xiaomi_mi-router-wr30u-112m-nmbm\n.*?"
    r"TARGET_DEVICES \+= xiaomi_mi-router-wr30u-112m-nmbm\n\n?",
    re.S,
)
if profile_pattern.search(image):
    image = profile_pattern.sub(profile_text + "\n", image, count=1)
else:
    image = image.replace(stock_anchor, profile_text + "\n" + stock_anchor, 1)
IMAGE.write_text(image)

# 将 custom compatible 加入与 WR30U stock 相同的板级处理分支。
def add_compat(path: Path, expected_occurrences: int):
    text = path.read_text()
    stock_pattern = re.compile(
        r"^(?P<indent>[ \t]*)xiaomi,mi-router-wr30u-stock\|\\$", re.M
    )
    custom_pattern = re.compile(
        rf"^[ \t]*{re.escape(COMPAT)}\|\\$", re.M
    )

    present_count = len(custom_pattern.findall(text))
    if present_count == expected_occurrences:
        return
    if present_count != 0:
        raise SystemExit(f"ERROR: {path} 中 custom compatible 出现次数异常：{present_count}。")

    matches = list(stock_pattern.finditer(text))
    if len(matches) != expected_occurrences:
        raise SystemExit(
            f"ERROR: {path} 中 WR30U stock 锚点数量为 {len(matches)}，"
            f"预期 {expected_occurrences}。"
        )

    text = stock_pattern.sub(
        lambda m: f"{m.group('indent')}{COMPAT}|\\\n{m.group(0)}",
        text,
    )
    path.write_text(text)

# 3–6. LED、网络/MAC、U-Boot env、preinit/failsafe 网口。
add_compat(LEDS, 1)
add_compat(NETWORK, 2)
add_compat(ENVTOOLS, 1)
add_compat(PREINIT, 1)

# 7. sysupgrade：该 custom U-Boot 历史上从 UBI volume "fit" 启动。
#    若不设置，nand.sh 默认 CI_KERNPART=kernel，升级后可能写错卷名。
platform = PLATFORM.read_text()
existing_case = re.compile(
    r"^[ \t]*xiaomi,mi-router-wr30u-112m-nmbm\)\n"
    r"(?:^[ \t].*\n)*?^[ \t]*;;\n",
    re.M,
)
existing_matches = list(existing_case.finditer(platform))
if len(existing_matches) > 1:
    raise SystemExit("ERROR: platform.sh 中 custom upgrade case 出现多次。")
if existing_matches:
    platform = existing_case.sub(platform_case, platform, count=1)
else:
    upgrade_anchor = (
        "\txiaomi,mi-router-ax3000t|\\\n"
        "\txiaomi,mi-router-wr30u-stock|\\\n"
        "\txiaomi,redmi-router-ax6000-stock)\n"
        "\t\tCI_KERN_UBIPART=ubi_kernel\n"
    )
    if platform.count(upgrade_anchor) != 1:
        raise SystemExit("ERROR: 无法唯一定位 24.10.6 的 WR30U stock upgrade 分支。")
    platform = platform.replace(upgrade_anchor, platform_case + upgrade_anchor, 1)
PLATFORM.write_text(platform)

# 最终强校验。
if DTS.read_text() != dts_text:
    raise SystemExit("ERROR: DTS 最终内容校验失败。")

final_image = IMAGE.read_text()
profile_match = profile_pattern.search(final_image)
if not profile_match:
    raise SystemExit("ERROR: 最终 image profile 不存在。")
profile_block = profile_match.group(0)

required_profile_lines = [
    "DEVICE_DTS := mt7981b-xiaomi-mi-router-wr30u-112m-nmbm",
    "UBINIZE_OPTS := -E 5",
    "BLOCKSIZE := 128k",
    "PAGESIZE := 2048",
    "DEVICE_PACKAGES := kmod-mt7915e kmod-mt7981-firmware mt7981-wo-firmware",
    "ARTIFACT/initramfs-factory.ubi := append-image-stage initramfs-kernel.bin | ubinize-kernel",
    "IMAGE/sysupgrade.bin := sysupgrade-tar | append-metadata",
]
for line in required_profile_lines:
    if line not in profile_block:
        raise SystemExit(f"ERROR: profile 缺少：{line}")

for unsafe in ("KERNEL_IN_UBI", "IMAGES += factory.bin", "IMAGE/factory.bin"):
    if unsafe in profile_block:
        raise SystemExit(f"ERROR: profile 中仍包含不应默认启用的构建项：{unsafe}")

checks = {
    LEDS: 1,
    NETWORK: 2,
    ENVTOOLS: 1,
    PREINIT: 1,
}
for path, expected in checks.items():
    count = path.read_text().count(COMPAT)
    if count != expected:
        raise SystemExit(
            f"ERROR: {path} 验证失败：匹配 {count} 次，预期 {expected} 次。"
        )

platform = PLATFORM.read_text()
if platform.count("xiaomi,mi-router-wr30u-112m-nmbm)") != 1:
    raise SystemExit("ERROR: platform.sh 的 custom case 数量错误。")
if platform_case not in platform:
    raise SystemExit("ERROR: platform.sh 未正确设置 CI_KERNPART=fit。")

preinit = PREINIT.read_text()
preinit_group = re.compile(
    r"xiaomi,mi-router-ax3000t\|\\\n.*?"
    r"xiaomi,mi-router-wr30u-112m-nmbm\|\\\n.*?"
    r"ifname=lan4",
    re.S,
)
if not preinit_group.search(preinit):
    raise SystemExit("ERROR: custom compatible 未进入 preinit 的 lan4 分支。")

print("WR30U 112M NMBM 已完整适配到 ImmortalWrt v24.10.6。")
print("构建产物：sysupgrade.bin；启用 initramfs 时另有 initramfs-factory.ubi。")
PY

if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  git diff --check
fi

echo
echo "最终 WR30U custom profile："
sed -n "/^define Device\/${PROFILE}$/,/^TARGET_DEVICES += ${PROFILE}$/p" \
  target/linux/mediatek/image/filogic.mk

echo
echo "最终 sysupgrade 分支："
sed -n "/^[[:space:]]*${COMPAT})$/,/^[[:space:]]*;;$/p" \
  target/linux/mediatek/filogic/base-files/lib/upgrade/platform.sh
