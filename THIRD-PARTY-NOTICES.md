# 第三方组件与许可

本仓库自身使用 MIT（见 LICENSE）。运行时可能涉及以下第三方组件：

| 组件 | 用途 | 许可 | 是否随安装包分发 |
|---|---|---|---|
| .NET 8 / WPF | 桌面界面运行时 | MIT | 否（框架依赖，用户需自装运行时） |
| Windows Subsystem for Linux | 运行抽屉 | Microsoft 许可 | 否（系统组件） |
| Ubuntu Base 24.04 | 抽屉根文件系统 | 多种自由许可（GPL/LGPL/BSD 等） | 否（首次构建时下载） |
| wslu | 箱内 wslview/wslpath | GPL-3.0 | 否（构建时 apt 安装） |
| restic | 可选增量快照 | BSD-2-Clause | 否（用户自行放置 restic.exe） |
| zstd | 可选快照压缩 | BSD-3-Clause（另有 GPLv2 双许可） | 否（用户自行放置 zstd.exe） |
| XFCE / xserver-xephyr 等 | 可选完整桌面 | GPL/LGPL | 否（首次点桌面时 apt 安装） |

说明：

- 安装包只包含本项目自身代码（MIT）。
- 抽屉里的系统与软件由用户在构建时从 Ubuntu 源安装，其许可随对应软件包。
- 如果你把预装环境的基础镜像再分发，需要自行核对镜像内软件的许可与署名要求。
