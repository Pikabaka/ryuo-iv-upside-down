# ROG RYUO IV Upside-Down Mount Screen Fix

**English** | [简体中文](README.zh-CN.md)

Mounted your ROG RYUO IV pump upside down? This flips the LCD back. It runs on the screen device itself. Once Android boots, it rotates the HomeUI text, the hardware stats overlay and fullscreen video by 180°. Armoury Crate / Info Hub still sends PC temperature, load and other data as usual.

## Tested on

- Device codename `cm16`, Rockchip RK3562, Android 13, firmware **V1.0.10**, HomeUI **1.7.6**, `arm64-v8a`.
- Verified:
  - 2240×1080 fullscreen video and the data overlay flip together.
  - The rotation comes back automatically after the screen reboots.
  - Disabling the service restores the original orientation.
- Split screen, other firmware versions and other models are untested.
- The boot animation plays before HomeUI starts, so it stays in the original orientation.

## How it works

The panel's physical resolution is 1080×2240. The stock display pipeline already lays it out as a 2240×1080 landscape screen. On this device:

- changing Android's system rotation once caused the device to reboot;
- Info Hub's `rotate` command only stores the angle and the picture does not change.

So this project adjusts two layers of content inside the stock HomeUI process instead.

1. **Text and UI**: on the Android main thread, set HomeUI's `DecorView` to `setRotation(180)`. Text, images and the data overlay in the view tree all flip with it.
2. **Video**: the stock player renders through a `SurfaceView`, which is a separate composition layer. Rotating the view tree alone leaves the video in its original orientation. The script:
   - finds the visible fullscreen `SurfaceView`;
   - reads its `mSurfaceControl` container and actual buffer size;
   - updates the matrix and position in a single `SurfaceControl.Transaction`.

   With display size `W × H` and buffer size `w × h`:

   ```text
   scaleX = W / w
   scaleY = H / h
   x' = W - scaleX * x
   y' = H - scaleY * y
   ```

   For example, a 1920×960 video on a 2240×1080 screen must keep its original horizontal and vertical scale. Applying a plain `-1, -1` shifts the video and leaves black bars. The matrix and position must be committed together.
3. **Start on boot**: a new `/vendor/etc/init/ryuo180.rc` starts the on-device script in Android's `boot` stage. The script:
   - waits for `sys.boot_completed=1`;
   - confirms HomeUI is running;
   - uses the local `frida-inject` to load the logic above;
   - watches HomeUI's process ID, and stops re-injecting if the app exits soon after an injection.

   The runtime logic also re-applies the transform when it detects a new fullscreen video layer or a new buffer size.

The stock APK, boot image, Android rotation settings and media files are left untouched. The resident script runs only on the device, and the injector does not open any network listening port.

## Files

| File | Purpose |
| --- | --- |
| [device/rotate.js](device/rotate.js) | The two-layer 180° rotation logic |
| [device/start.sh](device/start.sh) | Waits for Android and HomeUI, then starts local injection |
| [device/ryuo180.rc](device/ryuo180.rc) | Android init boot entry |
| [device/control.sh](device/control.sh) | Installs the boot entry; shows status; enables, disables or removes it |
| [tools/build.py](tools/build.py) | Downloads, verifies and assembles pinned Frida dependencies |

## Build

Requires Python 3.10+. From the repository root:

```sh
python tools/build.py
```

The build:

- downloads pinned versions from Frida and PyPI;
- verifies their SHA-256;
- generates `dist/`.

`dist/rotate.bundle.js` combines Frida's Java bridge with this project's rotation code. The repo holds source only. `dist/`, firmware images and stock APKs are not committed.

## Install

**This step adds an init file to the device's `vendor` partition.** Before you start:

1. Back up the partition and verify the image.
2. Confirm that you can enter the stock Recovery.
3. Confirm that you can get root over ADB.
4. Confirm that you can boot back into the normal system.

The installer only accepts the stock `vendor` image hash tested by this project. If the hash differs, it stops.

Run `adb devices -l` first, and replace every `SERIAL` below with your cooler screen's serial number. If you use the ADB bundled with Info Hub, run it from the Info Hub program folder so it can load its DLLs.

```sh
adb -s SERIAL shell id
adb -s SERIAL shell getprop ro.product.device
adb -s SERIAL shell 'test ! -e /data/local/ryuo180 && mkdir -m 700 /data/local/ryuo180'
```

The first command should return root and the second should return `cm16`. If the last command fails, find out where the existing directory came from first. Continue only after the directory has been created.

```sh
adb -s SERIAL push dist/inject /data/local/ryuo180/inject
adb -s SERIAL push dist/rotate.bundle.js /data/local/ryuo180/rotate.bundle.js
adb -s SERIAL push dist/start.sh /data/local/ryuo180/start.sh
adb -s SERIAL push dist/ryuo180.rc /data/local/ryuo180/ryuo180.rc
adb -s SERIAL push dist/control.sh /data/local/ryuo180/control.sh
adb -s SERIAL shell 'chmod 700 /data/local/ryuo180/inject && chmod 600 /data/local/ryuo180/rotate.bundle.js /data/local/ryuo180/start.sh /data/local/ryuo180/ryuo180.rc /data/local/ryuo180/control.sh'
adb -s SERIAL shell sh /data/local/ryuo180/control.sh install-inactive
```

First reboot the screen with the flip still disabled, and confirm the stock UI starts. Then enable it and reboot again to verify it applies on boot.

```sh
adb -s SERIAL reboot
# Wait for the device to reconnect and Android to finish booting, then run:
adb -s SERIAL shell sh /data/local/ryuo180/control.sh enable
adb -s SERIAL reboot
# After the device reconnects, verify:
adb -s SERIAL shell sh /data/local/ryuo180/control.sh status
adb -s SERIAL shell logcat -d -s RYUO180
```

The log should show `Applied UI and video rotation`. Also check on the screen that the video is playing and the numbers are updating. If hardware data does not show up yet, re-apply the current theme in Info Hub.

## Revert

To disable the flip and restore the stock orientation:

```sh
adb -s SERIAL shell sh /data/local/ryuo180/control.sh disable
```

After disabling, you can also remove the boot entry:

```sh
adb -s SERIAL shell sh /data/local/ryuo180/control.sh remove-startup
```

- `disable` removes the enable flag, stops the service and restarts HomeUI.
- `remove-startup` deletes only this project's init file, after checking that it matches.

Recovery could see the original partitions over ADB in testing, but **flashing the original image back as a rollback has not been rehearsed**. A Fastboot temporary-boot command once reported success, but the device dropped back to the bootloader. Do not treat it as a verified recovery path.

## References

- [FoxPodZ/ryuo-iv-screen](https://github.com/FoxPodZ/ryuo-iv-screen): reverse engineering of the RYUO IV protocol, ADB access and the stock apps.
- [Android 13 init documentation](https://android.googlesource.com/platform/system/core/+/refs/heads/android13-release/init).
- [Frida Android docs](https://frida.re/docs/android/) · [Frida 17.26.2](https://github.com/frida/frida/releases/tag/17.26.2) · [frida-tools 14.13.0](https://pypi.org/project/frida-tools/14.13.0/).
