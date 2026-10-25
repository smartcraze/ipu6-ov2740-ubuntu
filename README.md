# Intel IPU6 + OV2740 webcam on Ubuntu 26.04

Fixes a green, noisy, or missing webcam on laptops with an **Intel IPU6 (Alder Lake)** imaging
unit and an **OV2740** sensor. Tested on an **Acer Swift SF314-71** with Ubuntu 26.04
(kernel 7.0.0-38-generic, Secure Boot on). It may work on other Alder Lake laptops with the same
sensor; it has not been tested on them.

## The problem

The kernel detects the camera, but the default stack (libcamera's software ISP) has no tuning
for the OV2740. The picture comes out strongly green, dark and grainy. Windows looks good because
it uses the chip's hardware ISP with Intel's tuning data.

## What this does

| Step | Why |
|---|---|
| Install `linux-modules-ipu6-generic-hwe-*` | Signed `intel_ipu6_psys` driver: gives `/dev/ipu-psys0` (hardware ISP). No DKMS, no Secure Boot key enrolment. |
| Install Intel's HAL (`libcamhal-ipu6ep`, `gstreamer1.0-icamera`) from the [OEM Solutions Group PPA](https://launchpad.net/~oem-solutions-group/+archive/ubuntu/intel-ipu6) | Intel's camera pipeline and its OV2740 tuning. The PPA is pinned to priority 100, so it never replaces Ubuntu packages. |
| Add `ov2740-uf-0` to `libcamhal_profile.xml` | The stock profile only looks for the sensor on CSI port 1; many laptops use port 0. |
| `v4l2-relayd` + `v4l2loopback` | Exposes Intel's pipeline as a normal webcam named "Intel MIPI Camera". |
| Placeholder `SPLASHSRC` | Without it the loopback device looks output-only and PipeWire offers no camera. |
| One consistent `card_label` | Ubuntu's default ("Virtual Camera") conflicted with the PPA's, and the relay service could not find its device. |
| dracut config adding `ipu6ep_fw.bin` to the boot image | `intel_ipu6` does not declare its firmware, so dracut (which builds the initramfs on Ubuntu 26.04) leaves it out. The driver probes in early boot, fails with `-ENOENT`, and the camera is gone after every reboot. |
| WirePlumber rules | Hide the raw sensor nodes and libcamera camera so apps (Snapshot, browsers) only see the working one. |

## Install

```
git clone <this repo> && cd ipu6-ov2740-ubuntu
sudo ./install.sh
sudo reboot
```

Then open **Snapshot** and pick **Intel MIPI Camera (V4L2)**. In Brave/Chromium, enable
`brave://flags/#enable-webrtc-pipewire-camera` and relaunch. The camera takes 2-3 seconds to wake
when an app first asks for video.

Other chips: set `PLATFORM=ipu6epmtl` (Meteor Lake) and adjust `FW_FILE` if needed, e.g.
`sudo PLATFORM=ipu6epmtl ./install.sh`. Untested.

### Optional: Acer's own tuning (SF314-71)

Acer's Windows camera driver ships a tuning file for its camera module
(`OV2740_CJFKF28_ADL.aiqb`, selected by `ov2740_extension_acer.inf`). It is Acer's file, so it is
**not included here**. Download the camera driver for your model from acer.com, then:

```
sudo ./apply-acer-tuning.sh ~/Downloads/Camera_Intel_63.22000.3.6744_W11x64_A.zip
sudo ./apply-acer-tuning.sh --revert      # go back
```

The script reads one file from the zip, checks its SHA-256, and runs nothing from the package.
In a side-by-side test the Acer file gave a slightly darker, more natural exposure and warmer
colours; judge it yourself on your own camera.

## Caveats

- The PPA is a **development PPA** and unsupported. If the camera breaks after a kernel update,
  first try `sudo apt install linux-modules-ipu6-generic-hwe-26.04` and reboot.
- Only Ubuntu 26.04 is tested (`FORCE=1` skips the version check).
- Verified on one machine: the camera comes up on its own after reboot (driver, firmware and
  relay all start at boot). `install.sh` and `apply-acer-tuning.sh` were written from those
  steps but have not been run end to end on a clean install.
- Ubuntu 26.04 builds the initramfs with **dracut**; hooks in `/etc/initramfs-tools/hooks/` are
  not used. That is why the firmware fix is a file in `/etc/dracut.conf.d/`.

## Uninstall

```
sudo ./uninstall.sh && sudo reboot
```

## Licence

MIT for the scripts in this repo. Intel's HAL and tuning data come from the PPA and Acer's
tuning file from Acer; none of them are redistributed here.
