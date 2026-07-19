#!/usr/bin/env bash
set -euo pipefail

PROFILE="xiaomi_mi-router-wr30u-112m-nmbm"
COMPAT="xiaomi,mi-router-wr30u-112m-nmbm"

fail() {
  echo "ERROR: $*" >&2
  exit 1
}

[ -f target/linux/mediatek/image/filogic.mk ] \
  || fail "请在 ImmortalWrt 24.10 源码根目录运行此脚本。"

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
VERSION = Path("include/version.mk")

required = [IMAGE, LEDS, NETWORK, ENVTOOLS, PREINIT, PLATFORM, VERSION]
for path in required:
    if not path.is_file():
        raise SystemExit(f"ERROR: 缺少源码文件：{path}")

# 仅面向 ImmortalWrt 24.10.x；24.10.6 已按用户提供的原始源码实际核对。
version_text = VERSION.read_text()
version_match = re.search(
    r"VERSION_NUMBER:=\$\(if \$\(VERSION_NUMBER\),\$\(VERSION_NUMBER\),([^\)]+)\)",
    version_text,
)
if not version_match:
    raise SystemExit("ERROR: 无法识别 ImmortalWrt 版本号，源码结构可能不是 24.10。")
version_number = version_match.group(1).strip()
if not version_number.startswith("24.10"):
    raise SystemExit(
        f"ERROR: 当前源码版本为 {version_number}，本脚本仅用于 ImmortalWrt 24.10.x。"
    )

# 来自 ImmortalWrt 23.05.7 官方 WR30U 112M NMBM DTS。
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

# 以 23.05.7 官方 Profile 为基准，仅做 24.10 必要适配：
# 1. 补入 24.10 所需的 kmod-mt7915e；
# 2. 使用 24.10 当前 Profile 的 ImageBuilder 防护层。
profile_text = '''define Device/xiaomi_mi-router-wr30u-112m-nmbm
  DEVICE_VENDOR := Xiaomi
  DEVICE_MODEL := Mi Router WR30U
  DEVICE_VARIANT := (custom U-Boot layout)
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

# 1. DTS：精确写入最终内容。
if DTS.exists() and DTS.read_text() != dts_text:
    raise SystemExit(
        f"ERROR: {DTS} 已存在但内容不同，请先检查是否应用过其他 WR30U 分区补丁。"
    )
DTS.write_text(dts_text)

# 2. Image Profile：替换旧版/不完整恢复，或插入到 stock Profile 之前。
image = IMAGE.read_text()
stock_anchor = "define Device/xiaomi_mi-router-wr30u-stock\n"
if image.count(stock_anchor) != 1:
    raise SystemExit("ERROR: 无法唯一定位 WR30U stock Profile；源码可能不是受支持的 24.10 结构。")

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

# Helper：将 custom compatible 直接插入 WR30U stock 条目之前。
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

# 3–6. 板级集成：LED、接口/MAC、U-Boot env、preinit/failsafe lan4。
add_compat(LEDS, 1)
add_compat(NETWORK, 2)
add_compat(ENVTOOLS, 1)
add_compat(PREINIT, 1)

# 7. 24.10 sysupgrade：显式固定为官方 23.05.7 Profile 对应的
#    单一 ubi 分区 + kernel/rootfs UBI volume。
platform = PLATFORM.read_text()

# 清除其他恢复脚本可能加入的错误 fit 分支或旧 custom 独立分支。
custom_case_pattern = re.compile(
    r"^[ \t]*xiaomi,mi-router-wr30u-112m-nmbm\)\n"
    r"(?:^[ \t]+.*\n)*?^[ \t]*;;\n",
    re.M,
)
platform = custom_case_pattern.sub("", platform)

# 防止 custom compatible 被错误塞入其他多设备 case group。
platform = re.sub(
    rf"^[ \t]*{re.escape(COMPAT)}\|\\\n",
    "",
    platform,
    flags=re.M,
)

stock_upgrade_anchor = (
    "\txiaomi,mi-router-ax3000t|\\\n"
    "\txiaomi,mi-router-wr30u-stock|\\\n"
    "\txiaomi,redmi-router-ax6000-stock)\n"
    "\t\tCI_KERN_UBIPART=ubi_kernel\n"
)
if platform.count(stock_upgrade_anchor) != 1:
    raise SystemExit(
        "ERROR: 无法唯一定位 24.10 platform.sh 中 WR30U stock 升级分支。"
    )

custom_upgrade_case = '''\txiaomi,mi-router-wr30u-112m-nmbm)
\t\tCI_UBIPART="ubi"
\t\tCI_KERNPART="kernel"
\t\tCI_ROOTPART="rootfs"
\t\tnand_do_upgrade "$1"
\t\t;;
'''
platform = platform.replace(
    stock_upgrade_anchor,
    custom_upgrade_case + stock_upgrade_anchor,
    1,
)
PLATFORM.write_text(platform)

# 最终验证。
checks = {
    DTS: (COMPAT, 1),
    IMAGE: (PROFILE, 2),       # define + TARGET_DEVICES
    LEDS: (COMPAT, 1),
    NETWORK: (COMPAT, 2),
    ENVTOOLS: (COMPAT, 1),
    PREINIT: (COMPAT, 1),
    PLATFORM: (COMPAT, 1),
}
for path, (needle, expected) in checks.items():
    count = path.read_text().count(needle)
    if count != expected:
        raise SystemExit(
            f"ERROR: {path} 验证失败：匹配 {count} 次，预期 {expected} 次。"
        )

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
        raise SystemExit(f"ERROR: Profile 缺少：{line}")

final_platform = PLATFORM.read_text()
required_upgrade_lines = [
    'CI_UBIPART="ubi"',
    'CI_KERNPART="kernel"',
    'CI_ROOTPART="rootfs"',
    'nand_do_upgrade "$1"',
]
for line in required_upgrade_lines:
    if line not in final_platform:
        raise SystemExit(f"ERROR: platform.sh custom 升级分支缺少：{line}")

# custom layout 绝不能进入 FIT/ubootmod 升级路径。
custom_case_match = re.search(
    r"xiaomi,mi-router-wr30u-112m-nmbm\)\n(.*?)\n[ \t]*;;",
    final_platform,
    re.S,
)
if not custom_case_match:
    raise SystemExit("ERROR: 无法读取 custom sysupgrade 分支。")
custom_case_body = custom_case_match.group(1)
if "fit_do_upgrade" in custom_case_body or 'CI_KERNPART="fit"' in custom_case_body:
    raise SystemExit("ERROR: custom layout 被错误配置为 FIT 升级路径。")

print(
    f"WR30U 112M NMBM custom layout 已写入 ImmortalWrt {version_number}。\n"
    "升级结构：MTD ubi -> UBI volumes kernel/rootfs/rootfs_data。"
)
PY

if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  git diff --check
fi

echo
echo "最终 WR30U custom Profile："
sed -n "/^define Device\/${PROFILE}$/,/^TARGET_DEVICES += ${PROFILE}$/p" \
  target/linux/mediatek/image/filogic.mk

echo
echo "最终 WR30U custom sysupgrade 分支："
sed -n "/^[[:space:]]*${COMPAT})$/,/^[[:space:]]*;;$/p" \
  target/linux/mediatek/filogic/base-files/lib/upgrade/platform.sh
