# m1ddc 来源

项目 https://github.com/waydabber/m1ddc

固定提交 `7339ceebb03f691b1eaeb8471dca301d215d19c8`，MIT 许可证见 LICENSE。

本地修改修复 i2c.m 中向 uint16_t 拷贝数据时使用 sizeof(2) 的长度错误，改用 sizeof(uint16_t)。读取回复增加长度、功能码、结果及校验和验证。

增加 `display list-json`，返回显示器 UUID 和 CoreGraphics ID，供 Gamma 调光与按设备恢复使用。

整理后仅保留 i2c 和 ioregistry 库文件。通用 CLI 已移除，应用专用亮度工具位于 Sources/Helpers/DDCBrightness.m，仅提供显示器 JSON 列表及亮度读写。硬件关机实验结论见 docs/experiments.md。
