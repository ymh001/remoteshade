# RemoteShade 1.0.0

本分支以 MonitorControl 为基础，接入 RemoteShade 的远控会话检测、DDC/Gamma 黑屏及恢复、锁屏闲置熄屏、系统自动休眠控制。上游版本固定在 UPSTREAM.md，原许可证保留。

## 使用与构建

运行 `./scripts/build.sh`，产物为 `build/remoteshade/RemoteShade.app`。运行 `./scripts/package.sh` 生成 `release/RemoteShade-1.0.0.dmg`。需要完整 Xcode，GitHub 依赖经用户指定 SOCKS5 代理获取。本版本为 Apple Silicon、macOS 26+，本地 ad-hoc 签名。

应用名称、图标、内部标识 cn.leaflab.display-guard 和 RemoteShade 设置沿用现有版本。全部设置页使用原生侧边栏与统一分组布局，显示器、键盘、高级页复用 MonitorControl 的设置动作和原生录入控件。菜单保留 MC 显示器滑块，并加入 RS 状态、远控黑屏快捷开关和立即熄屏。

## 控制协调

远控黑屏及恢复期间，由 RemoteShade 控制 DDC/Gamma。MC 的亮度写入、快捷键、同步和显示重配置暂缓，音量控制继续可用。Gamma 写入使用锁协调，DDC 已排队工作在交接前排空。恢复完成后重新启用亮度控制与轮询，显示器重配置请求延后执行。正常退出先恢复硬件和完整 Gamma 表，复用原异常恢复记录。

自动黑屏适用范围沿用已验证的 DDC 外接显示器。内建屏、虚拟屏的 MC 日常调光能力保留，自动隐私黑屏的范围尚待扩展。显示器兼容参数在单列布局中按功能折叠。原 MonitorControl 偏好设置独立保留，当前版的 MC 设置从本应用域开始记录。

当前版关闭上游更新入口和自动更新启动，避免被 MonitorControl 官方安装包替换。自启动由通用页的 SMAppService 管理。

## 验证记录

- Xcode 构建、深度签名校验通过。
- 集成亮度交接测试通过，覆盖进行中的 Gamma 写入、黑屏期间拒绝覆盖和恢复后重新启用。
- 原策略、输入闲置、Gamma 持久化、异常恢复、多显示器与系统休眠流程回归测试通过。
- 首个集成构建已在本机启动，通用设置窗口实际可见。
- 用户要求避免干扰使用后，后续修正仅后台构建。最终包未覆盖当时正在运行的较早集成构建。
- 待用户验收：各页切换与布局、亮度/音量滑块、媒体按键权限、远控黑屏期间的调光互斥、快速断连重连、热插拔及自启动。
- 0.5.14 的独立版基线保留在 main 和对应 DMG。
