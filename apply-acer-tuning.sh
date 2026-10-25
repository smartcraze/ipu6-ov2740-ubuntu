#!/bin/bash
# Use Acer's own OV2740 tuning (OV2740_CJFKF28_ADL.aiqb) instead of the PPA default.
# Acer's file is NOT in this repo. Download the camera driver for your model from acer.com
# (Camera_Intel_63.22000.3.6744_W11x64_A.zip for the SF314-71) and pass the zip:
#   sudo ./apply-acer-tuning.sh ~/Downloads/Camera_Intel_*.zip
#   sudo ./apply-acer-tuning.sh --revert
set -euo pipefail
PLATFORM="${PLATFORM:-ipu6ep}"
NAME="OV2740_CJFKF28_ADL"
SHA256="43c0afd6025a1412d5ee79eb9426bb1857274dad5af0d0569a63a589fa9cc1b8"
XML="/etc/camera/${PLATFORM}/sensors/ov2740-uf.xml"
DST="/etc/camera/${PLATFORM}/${NAME}.aiqb"

[ "$(id -u)" -eq 0 ] || { echo "Run as root: sudo $0 ..." >&2; exit 1; }

if [ "${1:-}" = "--revert" ]; then
    [ -e "${XML}.bak" ] && cp -f "${XML}.bak" "${XML}"
    rm -f "${DST}"
    systemctl restart v4l2-relayd
    echo "Reverted to the default tuning."; exit 0
fi

ZIP="${1:?usage: $0 <Acer camera driver zip> | --revert}"
TMP="$(mktemp -d)"; trap 'rm -rf "${TMP}"' EXIT
# Read one member straight out of the zip; nothing from the package is executed.
unzip -p "${ZIP}" "*${NAME}.aiqb" > "${TMP}/${NAME}.aiqb"
echo "${SHA256}  ${TMP}/${NAME}.aiqb" | sha256sum -c - \
    || { echo "Unexpected file contents; refusing to install." >&2; exit 1; }

[ -e "${XML}.bak" ] || cp -a "${XML}" "${XML}.bak"
install -m 644 "${TMP}/${NAME}.aiqb" "${DST}"
sed -i '/supportedTuningConfig/,/\/>/ s/OV2740_CJFLE23_ADL/'"${NAME}"'/g' "${XML}"
systemctl restart v4l2-relayd
echo "Acer tuning applied. Undo with: sudo $0 --revert"
