#!/usr/bin/env bash
set -euo pipefail

# Restore the removed Xiaomi Redmi Router AX6000 custom U-Boot layout
# in ImmortalWrt 24.10 by reversing the official removal commit.
#
# Run this script from anywhere inside a fresh ImmortalWrt Git checkout,
# before copying .config and before starting the build.

REMOVE_COMMIT="9334bf3ec1e21d0bc1b1f8dc480415aea589ebc7"
PROFILE_NAME="xiaomi_redmi-router-ax6000"
COMPATIBLE="xiaomi,redmi-router-ax6000"

fail() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}

command -v git >/dev/null 2>&1 || fail "git is required"
command -v python3 >/dev/null 2>&1 || fail "python3 is required"

git rev-parse --is-inside-work-tree >/dev/null 2>&1 \
    || fail "run this inside an ImmortalWrt Git checkout"

REPO_ROOT="$(git rev-parse --show-toplevel)"
cd "$REPO_ROOT"

[ -f target/linux/mediatek/image/filogic.mk ] \
    || fail "this does not look like an ImmortalWrt MediaTek/Filogic source tree"

# Do not let git revert overwrite unrelated local edits.
if ! git diff --quiet || ! git diff --cached --quiet; then
    fail "the source tree has uncommitted changes; use a fresh clone or commit/stash them first"
fi

DTS="target/linux/mediatek/dts/mt7986a-xiaomi-redmi-router-ax6000.dts"
IMAGE_MK="target/linux/mediatek/image/filogic.mk"
LEDS="target/linux/mediatek/filogic/base-files/etc/board.d/01_leds"
NETWORK="target/linux/mediatek/filogic/base-files/etc/board.d/02_network"
UBOOT_ENV="package/boot/uboot-envtools/files/mediatek_filogic"

has_profile=0
has_dts=0
has_leds=0
has_network=0
has_uboot_env=0

[ -f "$DTS" ] && has_dts=1
grep -q "^define Device/${PROFILE_NAME}$" "$IMAGE_MK" && has_profile=1
grep -q "^[[:space:]]*${COMPATIBLE}|\\\\$" "$LEDS" && has_leds=1
# The compatible should occur in both interface and MAC setup blocks.
[ "$(grep -c "^[[:space:]]*${COMPATIBLE}|\\\\$" "$NETWORK" || true)" -ge 2 ] \
    && has_network=1
grep -q "^[[:space:]]*${COMPATIBLE}|\\\\$" "$UBOOT_ENV" && has_uboot_env=1

restored_count=$((has_profile + has_dts + has_leds + has_network + has_uboot_env))

if [ "$restored_count" -eq 0 ]; then
    # A --depth=1 clone normally does not contain this older commit.
    # Fetch the commit and enough ancestry for Git to calculate its reverse diff.
    if ! git cat-file -e "${REMOVE_COMMIT}^{commit}" 2>/dev/null \
       || ! git cat-file -e "${REMOVE_COMMIT}^" 2>/dev/null; then
        echo "Fetching removal commit ${REMOVE_COMMIT} ..."
        git fetch --no-tags --depth=2 origin "$REMOVE_COMMIT"
    fi

    git cat-file -e "${REMOVE_COMMIT}^{commit}" 2>/dev/null \
        || fail "cannot obtain removal commit ${REMOVE_COMMIT}"
    git cat-file -e "${REMOVE_COMMIT}^" 2>/dev/null \
        || fail "cannot obtain the parent of ${REMOVE_COMMIT}"

    echo "Reversing official AX6000 custom-layout removal commit ..."
    if ! git revert --no-commit "$REMOVE_COMMIT"; then
        git revert --abort >/dev/null 2>&1 || true
        fail "git revert conflicted with this source revision; use the matching 24.10 tag or update the patch manually"
    fi
elif [ "$restored_count" -ne 5 ]; then
    fail "a partial AX6000 custom-layout restoration already exists (${restored_count}/5 checks passed). Start from a fresh clone; do not layer this script over the old incomplete script"
else
    echo "All five custom-layout components are already present; skipping git revert."
fi

# The historical profile removed by 9334bf3 did not explicitly include
# kmod-mt7915e. Current 24.10 AX6000 stock/ubootmod profiles do, so add it
# to ensure the Wi-Fi driver is built into the custom-layout image.
python3 - <<'PY'
from pathlib import Path

path = Path("target/linux/mediatek/image/filogic.mk")
text = path.read_text()
start_marker = "define Device/xiaomi_redmi-router-ax6000\n"
start = text.find(start_marker)
if start < 0:
    raise SystemExit("custom AX6000 profile was not restored")
end = text.find("\nendef", start)
if end < 0:
    raise SystemExit("cannot locate end of custom AX6000 profile")

block = text[start:end]
lines = block.splitlines()
for index, line in enumerate(lines):
    if line.lstrip().startswith("DEVICE_PACKAGES :="):
        if "kmod-mt7915e" not in line.split():
            if "kmod-leds-ws2812b" in line:
                line = line.replace(
                    "kmod-leds-ws2812b",
                    "kmod-leds-ws2812b kmod-mt7915e",
                    1,
                )
            else:
                line = line.rstrip() + " kmod-mt7915e"
            lines[index] = line
        break
else:
    raise SystemExit("DEVICE_PACKAGES was not found in custom AX6000 profile")

new_block = "\n".join(lines)
text = text[:start] + new_block + text[end:]
path.write_text(text)
PY

# Verify every file/entry removed by 9334bf3 has been restored.
[ -f "$DTS" ] || fail "missing restored DTS: $DTS"
grep -q "^define Device/${PROFILE_NAME}$" "$IMAGE_MK" \
    || fail "missing custom image profile in $IMAGE_MK"
grep -q "kmod-mt7915e" "$IMAGE_MK" \
    || fail "kmod-mt7915e was not added to the custom image profile"
grep -q "^[[:space:]]*${COMPATIBLE}|\\\\$" "$LEDS" \
    || fail "missing AX6000 LED board match"
[ "$(grep -c "^[[:space:]]*${COMPATIBLE}|\\\\$" "$NETWORK" || true)" -ge 2 ] \
    || fail "missing AX6000 interface/MAC board matches"
grep -q "^[[:space:]]*${COMPATIBLE}|\\\\$" "$UBOOT_ENV" \
    || fail "missing AX6000 uboot-envtools board match"

echo
echo "AX6000 custom U-Boot layout restored successfully."
echo "Restored components:"
echo "  1. Custom partition-layout DTS"
echo "  2. Filogic image profile"
echo "  3. Default WAN LED setup"
echo "  4. LAN/WAN and MAC-address setup"
echo "  5. uboot-envtools environment mapping"
echo "Additional 24.10 adjustment: kmod-mt7915e included in DEVICE_PACKAGES."
echo
echo "Next steps:"
echo "  ./scripts/feeds update -a"
echo "  ./scripts/feeds install -a"
echo "  select CONFIG_TARGET_DEVICE_mediatek_filogic_DEVICE_xiaomi_redmi-router-ax6000=y"
echo "  make defconfig"
