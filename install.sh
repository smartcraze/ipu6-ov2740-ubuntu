#!/bin/bash
# Set up the Intel IPU6 (Alder Lake) + OV2740 webcam on Ubuntu 26.04.
# Run with: sudo ./install.sh
# Tested: Acer Swift SF314-71, Ubuntu 26.04, kernel 7.0.0-38-generic, Secure Boot on.
set -euo pipefail

PPA="ppa:oem-solutions-group/intel-ipu6"
PPA_ORIGIN="LP-PPA-oem-solutions-group-intel-ipu6"
PLATFORM="${PLATFORM:-ipu6ep}"                       # Alder Lake. Meteor Lake: ipu6epmtl
FW_FILE="${FW_FILE:-intel/ipu/${PLATFORM}_fw.bin}"   # firmware the kernel driver needs at boot
RELAY_LABEL="Intel MIPI Camera"

[ "$(id -u)" -eq 0 ] || { echo "Run as root: sudo $0" >&2; exit 1; }
[ -n "${SUDO_USER:-}" ] || { echo "Run through sudo so the user config can be installed." >&2; exit 1; }

. /etc/os-release
if [ "${VERSION_ID}" != "26.04" ] && [ "${FORCE:-0}" != "1" ]; then
    echo "Tested on Ubuntu 26.04 only (found ${VERSION_ID}). Re-run with FORCE=1 to try anyway." >&2
    exit 1
fi
lspci -nn | grep -qi 'Imaging Signal Processor' || {
    echo "No Intel IPU imaging device found; this repo is not for your machine." >&2; exit 1; }

backup_once() { [ -e "$1" ] && [ ! -e "$1.bak" ] && cp -a "$1" "$1.bak" || true; }

echo "==> Installing signed IPU6 kernel modules (provides /dev/ipu-psys0) and v4l2loopback"
apt-get install -y "linux-modules-ipu6-generic-hwe-${VERSION_ID}" \
    "linux-modules-v4l2loopback-generic-hwe-${VERSION_ID}" v4l2-relayd

echo "==> Adding the Intel IPU6 PPA, pinned low so it never replaces Ubuntu packages"
add-apt-repository -y "${PPA}"
printf 'Package: *\nPin: release o=%s\nPin-Priority: 100\n' "${PPA_ORIGIN}" \
    > /etc/apt/preferences.d/ipu6-ppa.pref
apt-get update
apt-get install -y "libcamhal-${PLATFORM}" gstreamer1.0-icamera

echo "==> Letting the HAL find the sensor on CSI port 0 (stock profile lists port 1 only)"
PROFILE="/etc/camera/${PLATFORM}/libcamhal_profile.xml"
backup_once "${PROFILE}"
grep -q 'ov2740-uf-0' "${PROFILE}" || sed -i 's/ov2740-uf-1,/ov2740-uf-0,ov2740-uf-1,/' "${PROFILE}"

echo "==> Making the loopback device name consistent (Ubuntu default says 'Virtual Camera')"
backup_once /etc/modprobe.d/v4l2-relayd.conf
echo "options v4l2loopback devices=1 exclusive_caps=1 card_label=\"${RELAY_LABEL}\"" \
    > /etc/modprobe.d/v4l2-relayd.conf

echo "==> Configuring v4l2-relayd (1920x1080, with a placeholder so PipeWire sees a camera)"
backup_once /etc/v4l2-relayd.d/default.conf
cat > /etc/v4l2-relayd.d/default.conf <<CONF
VIDEOSRC=icamerasrc buffer-count=7
FORMAT=NV12
WIDTH=1920
HEIGHT=1080
FRAMERATE=30/1
CARD_LABEL=${RELAY_LABEL}
SPLASHSRC="videotestsrc pattern=black num-buffers=4 ! videoscale ! videoconvert"
CONF

echo "==> Adding the IPU6 firmware to the initramfs (the driver loads before the root fs is mounted)"
cat > /etc/initramfs-tools/hooks/ipu6-firmware <<HOOK
#!/bin/sh
PREREQ=""
prereqs() { echo "\$PREREQ"; }
case "\$1" in prereqs) prereqs; exit 0;; esac
. /usr/share/initramfs-tools/hook-functions
add_firmware ${FW_FILE}
exit 0
HOOK
chmod 755 /etc/initramfs-tools/hooks/ipu6-firmware
update-initramfs -u -k all

echo "==> Hiding the raw sensor nodes and libcamera camera from PipeWire for ${SUDO_USER}"
USER_HOME="$(getent passwd "${SUDO_USER}" | cut -d: -f6)"
WP_DIR="${USER_HOME}/.config/wireplumber/wireplumber.conf.d"
sudo -u "${SUDO_USER}" mkdir -p "${WP_DIR}"
sudo -u "${SUDO_USER}" tee "${WP_DIR}/51-disable-libcamera.conf" > /dev/null <<'CONF'
# Hide the libcamera camera so apps only see the Intel IPU6 virtual camera (v4l2-relayd)
wireplumber.profiles = {
  main = {
    monitor.libcamera = disabled
  }
}
CONF
sudo -u "${SUDO_USER}" tee "${WP_DIR}/52-hide-ipu6-raw.conf" > /dev/null <<'CONF'
# Hide raw IPU6 sensor nodes; they cannot be streamed directly.
monitor.v4l2.rules = [
  {
    matches = [
      { device.name = "~v4l2_device.pci-0000_00_05.0*" }
    ]
    actions = {
      update-props = {
        device.disabled = true
      }
    }
  }
]
CONF

echo "==> Starting the relay"
systemctl daemon-reload
systemctl stop v4l2-relayd 2>/dev/null || true
modprobe -r v4l2loopback 2>/dev/null || true
modprobe v4l2loopback
systemctl enable v4l2-relayd
systemctl reset-failed 'v4l2-relayd*' 2>/dev/null || true
systemctl restart v4l2-relayd
sudo -u "${SUDO_USER}" XDG_RUNTIME_DIR="/run/user/$(id -u "${SUDO_USER}")" \
    systemctl --user restart wireplumber pipewire || true

echo
echo "Done. Reboot once, then open Snapshot and pick '${RELAY_LABEL} (V4L2)'."
echo "Brave/Chromium: enable brave://flags/#enable-webrtc-pipewire-camera"
echo "Optional (Acer SF314-71): sudo ./apply-acer-tuning.sh ~/Downloads/Camera_Intel_*.zip"
