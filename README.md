# Acer Swift 3 (SF314-71) webcam on Ubuntu 26.04

Working, good-quality webcam on the **Acer Swift 3 SF314-71** under Ubuntu 26.04, using the
camera's **original calibration**: the tuning file Acer ships for this laptop's camera module in
its official Windows driver (the same file Windows loads), so colour, white balance and exposure
follow Acer's own tuning for this camera module.

| | |
|---|---|
| Laptop | Acer Swift 3 **SF314-71** |
| Camera | OmniVision **OV2740** (2 MP, MIPI, ACPI `INT3474`) on CSI port 0 |
| Imaging unit | Intel **IPU6** (Alder Lake, `ipu6ep`) |
| Tested on | Ubuntu 26.04, kernel 7.0.0-38-generic, Secure Boot on |
| Calibration | `OV2740_CJFKF28_ADL.aiqb` from Acer's camera driver `Camera_Intel_63.22000.3.6744_W11x64_A.zip` |

Other Alder Lake laptops with an OV2740 may work with the generic steps, but have not been tested,
and Acer's calibration only fits Acer's module.

## The problem

The kernel detects the camera, but Ubuntu's default stack (libcamera's software ISP) has no
calibration for the OV2740. The picture comes out strongly green, dark and grainy. Windows looks
good because it runs the camera through the chip's hardware ISP with the module's calibration
file. This repo does the same on Linux.

### Which calibration file is the original one

Acer's camera driver package contains two OV2740 calibrations. Intel's generic `ov2740.inf`
installs `OV2740_4SF259T2_ADL`, but Acer's extension `ov2740_extension_acer.inf` (bound to the
same `ACPI\INT3474` sensor) overrides it with **`OV2740_CJFKF28_ADL`**. On Windows the extension
wins, so `CJFKF28` is the calibration this laptop actually uses. Intel's Linux PPA only carries
`OV2740_CJFLE23_ADL`, a calibration for a Lenovo ThinkPad module; it works, but it was not made
for Acer's camera.

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
| Acer calibration `OV2740_CJFKF28_ADL.aiqb` (step 2) | The camera module's original tuning from Acer's driver, replacing the PPA's Lenovo-module tuning. |
| WirePlumber rules | Hide the raw sensor nodes and libcamera camera so apps (Snapshot, browsers) only see the working one. |

## Step 1: install

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

## Step 2: apply the original Acer calibration (SF314-71)

`install.sh` starts with the PPA's calibration (made for a Lenovo module). To use the camera's
original Acer calibration, download the camera driver for the SF314-71 from
[acer.com](https://www.acer.com/in-en/support/product-support/SF314-71) (Drivers and Manuals,
Windows, Camera), then:

```
sudo ./apply-acer-tuning.sh ~/Downloads/Camera_Intel_63.22000.3.6744_W11x64_A.zip
sudo ./apply-acer-tuning.sh --revert      # go back to the PPA calibration
```

The file belongs to Acer, so it is **not included in this repo**. The script reads that one file
from the zip, checks its SHA-256, installs it and selects it; nothing from the Windows package is
executed. In a side-by-side test on the SF314-71 it gave a more natural exposure (the wall was no
longer blown out) and warmer, more accurate colours than the Lenovo calibration.

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
