# 隐私政策

Drawer 不收集遥测、分析或广告数据。

## 本地数据

| 数据 | 位置 |
|---|---|
| 设置 | `%USERPROFILE%\.boxrun\settings.json` |
| 抽屉列表 | `%USERPROFILE%\.boxrun\boxes.json` |
| 标签 / 别名 | `%USERPROFILE%\.boxrun\tags.json`、`aliases.json` |
| 日志 | `%USERPROFILE%\.boxrun\logs\` |
| 崩溃报告 | `%USERPROFILE%\.boxrun\crashes\` |
| restic 密码 | `%USERPROFILE%\.boxrun\restic.pass` |

抽屉内容在用户选择的目录里。卸载程序不会删除抽屉、日志和设置。

## 什么时候联网

1. **检查更新**：只有用户配置了 `latest.json` 地址并点“检查更新”时，才读取该地址并下载安装包。
2. **崩溃上报（可选）**：只有用户配置了崩溃上报地址时，才把纯文本崩溃报告 POST 到该地址；不配置就只存本地。
3. **构建抽屉**：WSL 和 apt 按配置的镜像下载 Ubuntu 和软件包，这部分流量不经过本程序。

默认不向任何服务器发送数据。

## 第三方

WSL、Ubuntu 镜像、可选的 restic/zstd 有各自的隐私条款，见 [THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md)。

## 联系

在项目仓库提 issue。
