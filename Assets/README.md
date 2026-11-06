# RemoteShade 图标

AppIcon.png 为用户选定的黑布遮住显示器效果，由内置 imagegen 生成，用于应用与 DMG 内的应用图标。构建脚本生成标准多尺寸 ICNS。

MenuBarReference.png 为用户选定的白色幕帘效果，帘布越过屏幕下边缘，中央开口缩小一半。正式菜单栏图标按该轮廓以 AppKit 路径绘制，源文件为 Sources/App/MenuBarIcon.swift，以适配 22×20 点尺寸和系统模板着色。原图保留作设计参考。

应用图标生成提示为“macOS app icon, silver desktop monitor almost fully covered by matte black draped fabric, broad folds, silver stand visible, soft pale grey rounded-square tile, transparent outside margin, no text”。

菜单栏最终编辑提示为“white desktop monitor with two naturally draping white curtains extending below the bottom bezel; reduce central transparent opening width by half symmetrically; preserve folds, outer edges, rail and pedestal; transparent background”。
