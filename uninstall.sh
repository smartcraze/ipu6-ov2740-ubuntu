#!/bin/bash
# Undo install.sh. Run with: sudo ./uninstall.sh
set -uo pipefail
[ "$(id -u)" -eq 0 ] || { echo "Run as root: sudo $0" >&2; exit 1; }
PLATFORM="${PLATFORM:-ipu6ep}"

restore() { [ -e "$1.bak" ] && mv -f "$1.bak" "$1" && echo "restored $1"; }

systemctl disable --now v4l2-relayd 2>/dev/null
apt-get purge -y "libcamhal-${PLATFORM}" gstreamer1.0-icamera   # purge drops the edited /etc/camera files
apt-get autoremove -y
rm -f /etc/apt/preferences.d/ipu6-ppa.pref
add-apt-repository -y --remove ppa:oem-solutions-group/intel-ipu6 2>/dev/null
apt-get update

restore /etc/modprobe.d/v4l2-relayd.conf
restore /etc/v4l2-relayd.d/default.conf
rm -f /etc/initramfs-tools/hooks/ipu6-firmware
update-initramfs -u -k all

if [ -n "${SUDO_USER:-}" ]; then
    H="$(getent passwd "${SUDO_USER}" | cut -d: -f6)"
    rm -f "$H/.config/wireplumber/wireplumber.conf.d/51-disable-libcamera.conf" \
          "$H/.config/wireplumber/wireplumber.conf.d/52-hide-ipu6-raw.conf"
fi
echo "Removed. Reboot to finish. (Kernel modules from Ubuntu were left installed.)"
