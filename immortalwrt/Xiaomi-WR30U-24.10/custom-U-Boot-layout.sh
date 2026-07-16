#!/usr/bin/env bash
set -euo pipefail

REMOVE_COMMIT="1b7e62b20b1735fcdc498a35e005afcd775abcf4"
PROFILE="xiaomi_mi-router-wr30u-112m-nmbm"

fail() {
  echo "ERROR: $*" >&2
  exit 1
}

git rev-parse --is-inside-work-tree >/dev/null 2>&1 \
  || fail "请在 ImmortalWrt 源码根目录运行此脚本。"

[ -z "$(git status --porcelain)" ] \
  || fail "源码树不是干净状态；请使用刚克隆的干净源码。"

if grep -Fq "define Device/${PROFILE}" target/linux/mediatek/image/filogic.mk 2>/dev/null; then
  echo "${PROFILE} 已存在，无需恢复。"
  exit 0
fi

if ! git cat-file -e "${REMOVE_COMMIT}^{commit}" 2>/dev/null; then
  echo "正在获取 WR30U 112M NMBM 删除提交及其父提交……"
  git fetch --no-tags --depth=2 origin "${REMOVE_COMMIT}"
fi

echo "正在反向恢复 WR30U 112M NMBM custom layout……"
git revert --no-commit "${REMOVE_COMMIT}"

DTS="target/linux/mediatek/dts/mt7981b-xiaomi-mi-router-wr30u-112m-nmbm.dts"
IMAGE="target/linux/mediatek/image/filogic.mk"
LEDS="target/linux/mediatek/filogic/base-files/etc/board.d/01_leds"
NETWORK="target/linux/mediatek/filogic/base-files/etc/board.d/02_network"
ENVTOOLS="package/boot/uboot-envtools/files/mediatek_filogic"

test -f "${DTS}" || fail "DTS 恢复失败。"
grep -Fq "define Device/${PROFILE}" "${IMAGE}" || fail "镜像 profile 恢复失败。"
grep -Fq "xiaomi,mi-router-wr30u-112m-nmbm" "${LEDS}" || fail "LED 配置恢复失败。"
grep -Fq "xiaomi,mi-router-wr30u-112m-nmbm" "${NETWORK}" || fail "网络/MAC 配置恢复失败。"
grep -Fq "xiaomi,mi-router-wr30u-112m-nmbm" "${ENVTOOLS}" || fail "uboot-envtools 配置恢复失败。"

git diff --check

echo
echo "WR30U 112M NMBM custom layout 已恢复："
sed -n "/define Device\/${PROFILE}/,/TARGET_DEVICES += ${PROFILE}/p" "${IMAGE}"
