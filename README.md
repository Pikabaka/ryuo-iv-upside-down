# ROG RYUO IV 屏幕旋转 180°

让倒装的 ROG RYUO IV 水冷屏在 Android 启动后自行翻转 HomeUI 的文字、硬件数据和全屏视频。旋转程序运行在屏幕设备上。Info Hub 仍负责发送 PC 温度、占用率等数据。

## 实测范围

- 设备代号 `cm16`，Rockchip RK3562，Android 13，固件 **V1.0.10**，HomeUI **1.7.6**，`arm64-v8a`。
- 已验证 2240×1080 全屏视频和数据叠层一起翻转、屏幕重启后自动生效，以及关闭服务后恢复原方向。
- 分屏、其他固件和其他型号未验证。开机动画在 HomeUI 启动前播放，因此仍是原方向。

## 原理

面板物理分辨率是 1080×2240，原厂显示管线已经把它横置为 2240×1080。这台设备上，改 Android 的系统旋转曾触发设备重启，而 Info Hub 的 `rotate` 命令只记录角度，实际画面没变。本方案在原厂 HomeUI 进程内调整两层内容。

1. **文字和 UI**：在 Android 主线程把 HomeUI 的 `DecorView` 设为 `setRotation(180)`。View 树里的文字、图片和数据叠层一起翻转。
2. **视频**：原厂播放器用 `SurfaceView` 输出独立的合成层。仅旋转 View 树时，视频仍按原方向显示。脚本找到可见的全屏 `SurfaceView`，读取其 `mSurfaceControl` 容器和实际缓冲区尺寸，用一次 `SurfaceControl.Transaction` 更新矩阵和位置。以显示尺寸 `W × H` 和缓冲区尺寸 `w × h` 计算：

   ```text
   scaleX = W / w
   scaleY = H / h
   x' = W - scaleX * x
   y' = H - scaleY * y
   ```

   例如，1920×960 的视频在 2240×1080 的屏幕上需要保留原有的横纵缩放。直接套 `-1, -1` 会让视频偏移并留下黑边。矩阵和位置必须一起提交。
3. **开机生效**：新增的 `/vendor/etc/init/ryuo180.rc` 在 Android 的 `boot` 阶段启动设备上的脚本。脚本等 `sys.boot_completed=1`，确认 HomeUI 已启动，再用本机 `frida-inject` 加载上面的逻辑。它监视 HomeUI 的进程号。如果应用在注入后很快退出，脚本停止继续注入。运行时逻辑也会在识别到新的全屏视频层或缓冲区尺寸时重新应用变换。

原厂 APK、启动镜像、Android 系统旋转参数和媒体文件沿用原样。常驻脚本只在设备上运行，注入器无需打开网络监听端口。

## 文件

| 文件 | 用途 |
| --- | --- |
| [device/rotate.js](device/rotate.js) | 两层 180° 旋转逻辑 |
| [device/start.sh](device/start.sh) | 等待 Android 和 HomeUI，启动本地注入 |
| [device/ryuo180.rc](device/ryuo180.rc) | Android init 开机入口 |
| [device/control.sh](device/control.sh) | 安装入口、查看状态、启用、关闭及移除入口 |
| [tools/build.py](tools/build.py) | 下载、校验并组装固定版本的 Frida 依赖 |

## 构建

需要 Python 3.10+。从仓库根目录运行：

```sh
python tools/build.py
```

构建会从 Frida 和 PyPI 下载固定版本，校验 SHA-256，再生成 `dist/`。其中 `rotate.bundle.js` 由 Frida 的 Java bridge 和本项目的旋转代码拼接而成。仓库只放源码，`dist/`、固件镜像和原厂 APK 不需要上传。

## 部署

**这一步会向设备的 `vendor` 分区增加一个 init 文件。** 动手前应先备份分区并校验镜像，实测能进入原厂 Recovery、通过 ADB 获得 root，并返回正常系统。安装脚本只接受本项目实测的原厂 `vendor` 镜像哈希。哈希不一致时会停下。

先运行 `adb devices -l`。把下面的 `SERIAL` 全部换成你的水冷屏序列号。使用 Info Hub 自带的 ADB 时，从 Info Hub 程序目录调用它，确保能加载配套 DLL。

```sh
adb -s SERIAL shell id
adb -s SERIAL shell getprop ro.product.device
adb -s SERIAL shell 'test ! -e /data/local/ryuo180 && mkdir -m 700 /data/local/ryuo180'
```

先确认前两条分别返回 root 和 `cm16`。如果最后一条失败，先检查已有目录的来源。目录新建成功后再继续。

```sh
adb -s SERIAL push dist/inject /data/local/ryuo180/inject
adb -s SERIAL push dist/rotate.bundle.js /data/local/ryuo180/rotate.bundle.js
adb -s SERIAL push dist/start.sh /data/local/ryuo180/start.sh
adb -s SERIAL push dist/ryuo180.rc /data/local/ryuo180/ryuo180.rc
adb -s SERIAL push dist/control.sh /data/local/ryuo180/control.sh
adb -s SERIAL shell 'chmod 700 /data/local/ryuo180/inject && chmod 600 /data/local/ryuo180/rotate.bundle.js /data/local/ryuo180/start.sh /data/local/ryuo180/ryuo180.rc /data/local/ryuo180/control.sh'
adb -s SERIAL shell sh /data/local/ryuo180/control.sh install-inactive
```

先在翻转关闭的状态下重启屏幕，确认原厂画面能启动。然后启用并再次重启，验证开机自动生效。

```sh
adb -s SERIAL reboot
# 等设备重新连接，并确认 Android 启动完成后再执行下一条。
adb -s SERIAL shell sh /data/local/ryuo180/control.sh enable
adb -s SERIAL reboot
# 等设备重新连接后验证。
adb -s SERIAL shell sh /data/local/ryuo180/control.sh status
adb -s SERIAL shell logcat -d -s RYUO180
```

日志应出现 `Applied UI and video rotation`。再检查屏幕上视频在动、数字在更新。如果暂时没有硬件数据，可以在 Info Hub 重新应用当前主题。

## 回退

关闭并恢复原厂方向：

```sh
adb -s SERIAL shell sh /data/local/ryuo180/control.sh disable
```

关闭后如需移除开机入口：

```sh
adb -s SERIAL shell sh /data/local/ryuo180/control.sh remove-startup
```

`disable` 会移除启用标记、停止服务并重启 HomeUI。 `remove-startup` 只删除比对过的本项目 init 文件。实测 Recovery 能通过 ADB 看到原始分区，但**没有实刷原始镜像做回退演练**。Fastboot 的临时引导命令曾返回成功，但设备又回到 bootloader，因此不要把它当成已验证的救援办法。

## 参考

- [FoxPodZ/ryuo-iv-screen](https://github.com/FoxPodZ/ryuo-iv-screen) — RYUO IV 协议、ADB 和原厂应用的逆向分析。
- [Android 13 init 文档](https://android.googlesource.com/platform/system/core/+/refs/heads/android13-release/init)。
- [Frida Android 文档](https://frida.re/docs/android/) · [Frida 17.26.2](https://github.com/frida/frida/releases/tag/17.26.2) · [frida-tools 14.13.0](https://pypi.org/project/frida-tools/14.13.0/)。
