# RemoteShade

macOS 远控屏幕隐私工具。通过 Apple 屏幕共享远程操作 Mac 时，将本地外接显示器画面调黑，保护桌面内容；连接结束后恢复显示。

同时提供锁屏、闲置熄屏和电源管理，并集成日常显示器亮度、音量与快捷键控制。

当前版本为 **1.0.0**，面向 Apple Silicon 和 macOS 26 及以上版本。显示器控制基于 MonitorControl，保留其 MIT 许可证与来源记录。

## 功能

- 检测 Apple 屏幕共享连接，以 DDC 和 Gamma 组合将外接屏调黑，连接结束后恢复。
- 管理锁屏后闲置熄屏、远控断开后自动锁屏、系统自动休眠及登录启动。
- 在菜单栏调节显示器亮度、音量和对比度。
- 统一设置侧边栏，按显示器配置控制方式、键盘快捷键及兼容参数。
- 提供系统屏幕共享设置跳转和悬浮操作指引。
- 提供辅助功能授权检测、拖拽添加应用指引和实际按键监听状态。
- 可选 GitHub 更新检查，自动检查默认关闭。
- 登录启动仅显示菜单栏图标，打开设置时显示 Dock 图标，关闭设置后隐藏 Dock 图标。

## 下载

从 [GitHub Releases](https://github.com/ymh001/remoteshade/releases/latest) 下载安装包及 SHA-256 校验文件。

## 构建与检查

需要完整 Xcode。执行 `./scripts/build.sh`，应用输出到 `build/remoteshade/RemoteShade.app`。执行 `./scripts/package.sh` 生成安装镜像。

开发构建采用本机 ad-hoc 签名，尚未进行 Developer ID 签名或公证。

远控检测目前针对 Apple 屏幕共享，硬件控制效果取决于显示器、连接方式和 DDC 支持。其他远控软件与显示器组合需要单独验证。

## 项目资料

- [集成与验证说明](App/README-RemoteShade.md)
- [设计说明](docs/design.md)
- [MonitorControl 来源](App/UPSTREAM.md)
- [m1ddc 来源](Vendor/m1ddc/UPSTREAM.md)

旧版独立实现保留在 `Sources`，可通过 `scripts/build-standalone.sh` 构建。
