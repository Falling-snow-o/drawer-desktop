# 交互与并发审计（2026-11-17）

范围：GUI（WPF）、引擎（PowerShell）、常驻 daemon、安装器、脚本测试之间的交互。
目标：找出跨模块**卡死、竞态、重入、缺锁、进程生命周期冲突**。

## 已确认并修复

| # | 严重度 | 问题 | 位置 | 修复 |
|---|---|---|---|---|
| 1 | 高 | 多条查询并发写 daemon stdin，JSON 行可能交错，导致解析失败/超时 | `EngineDaemon.QueryAsync` | 增加写入信号量，串行写；写失败重启进程重试一次 |
| 2 | 高 | `_proc` 在锁外读取，Dispose 与查询并发时可能 NRE/ObjectDisposed | `EngineDaemon` | 加锁取进程引用；`_disposed` 标记禁止关闭后重启 |
| 3 | 高 | 关闭窗口（隐藏到托盘）时也释放引擎客户端，重新打开会重建 daemon | `MainWindow.OnClosing` | 只在真正退出且不忙时释放 |
| 4 | 高 | 覆盖安装不检查运行中的实例，直接解压覆盖 → `IOException`，安装失败且退出码仍为 0 | `installer.RunInstall` | 解压前 `EnsureStopped`；失败时 `ExitCode=1` |
| 5 | 中 | 安装器强杀正在构建/快照的进程，可能留下半成品 | `installer` | 增加 `busy.json` 标记；有操作时中止安装而不是杀进程 |
| 6 | 中 | 注册表 `boxes.json` 读改写无锁、非原子，并发 add/remove 会丢条目或写坏 JSON | `engine/core.ps1` | 命名互斥量 + 临时文件原子替换；读者重试 |
| 7 | 中 | 选择防抖的 Tick 闭包引用了字段，旧 timer 的 tick 会停掉新 timer | `BoxList_SelectionChanged` | 捕获局部 timer 并校验是否仍是当前实例 |
| 8 | 中 | 模态窗口打开期间，主窗口 5 秒自动刷新继续在背后跑，和窗口里的引擎调用抢 WSL | `MainWindow._autoRefresh` | 有 owner 模态窗口时跳过刷新 |
| 9 | 低 | daemon 异常后永久降级为直连（daemon 被 Dispose 但 ready 仍为 true） | `EngineClient.CaptureAsync` | 重建 daemon 并后台预热 |
| 10 | 低 | 动作执行中仍能从面板打开状态墙/端口/协同/诊断，重复调用引擎 | 面板菜单处理 | 统一加 `_busy` 守卫 |

## 已验证的行为

| 场景 | 结果 |
|---|---|
| 空闲时 `Drawer.exe --quit` | 3 秒内退出 |
| 动作执行中 `--quit` | 被拒绝，进程存活，动作继续 |
| 动作结束后 `--quit` | 正常退出 |
| 运行中覆盖安装（新版本） | 优雅退出 + 安装，约 1 秒 |
| 运行中覆盖安装（旧版本，无 --quit） | 超时后 CloseMainWindow + Kill 兜底，约 13 秒 |
| 4 个并发 `add` 注册 | 4 个全部保留 |
| 忙时启动安装 | 中止安装并返回 1，不杀进程 |

## 仍然存在、但已评估可接受的风险

| 风险 | 说明 |
|---|---|
| daemon 单线程 | 慢查询（info 冷启动约 1 秒）会阻塞 list；已用 4.5 秒缓存降低频率 |
| 两个 GUI 实例 | 已有命名互斥量保证单实例；CLI 与 GUI 同时操作同一盒子仍可能让 WSL 操作排队 |
| 快照并发 | 同名快照并发创建没有全局锁；GUI 已用 `_busy` 禁止，CLI 并发需自行避免 |
| 引擎动作无全局锁 | 同时从 CLI 执行 build 和 GUI 执行 up，WSL 可能报错；不会损坏数据 |
| 安装器旧版本升级 | 新安装器的 `--quit` 对旧版本无效，需要等 10 秒超时后强杀（一次性） |
| 日志并发追加 | GUI 内基本都在 UI 线程；极端情况下 `File.AppendAllText` 抛异常已被吞掉 |

## 建议的后续（未做）

1. 快照名跨盒子互斥（经核查快照按盒子存储，跨盒子同名不会撞；已改为快照名校验 + 同名拒绝）
3. 安装器读取 `busy.json` 时支持“等待并重试”，而不是直接失败
4. daemon 增加并发工作线程或按方法分队列，避免慢查询阻塞 list

## 统一交互层（InteractionHub）

所有功能窗口不再各自为政，而是订阅同一组事件：

| 事件 | 发布者 | 订阅者 | 行为 |
|---|---|---|---|
| `BusyChanged(bool)` | 主窗口动作开始/结束 | 协同窗口 | 动作执行期间禁用协同窗口所有按钮 |
| `ActionCompleted(verb)` | 主窗口动作完成 | 端口 / 状态墙 / 信息 / 协同 | 自动重新加载自己的数据 |
| `BoxesChanged` | 列表刷新后 | 端口 / 状态墙 | 抽屉增删后同步刷新 |

规则：

- 主窗口动作进行中（`InteractionHub.IsBusy`）时，附属窗口**不主动刷新**，避免和动作抢 WSL
- 窗口关闭时退订，避免事件持有已关闭窗口
- `--quit` 会先关闭所有附属窗口，再关主窗口，避免残留模态循环

已验证：端口窗口打开时执行主窗口「自检」，端口窗口保持打开并在动作结束后刷新，进程无崩溃。

## 补充：按盒子动作锁（已实现）

- 命名互斥量：`Local\drawer-box-<盒子名>`
- 覆盖动作：`build / up / down / remove / rename / snap / snap-restore / snap-delete / restore / clean / install / uninstall`
- 冲突时立即失败：退出码 `2`，提示「正在执行另一个操作」
- 只读查询（`info / list / ports / about / collab`）不加锁，不会被动作长时间阻塞

验证：

```
外部持有 lab 的锁 → box.ps1 down lab
  ✗ 「lab」正在执行另一个操作，稍后再试
  exit=2
释放后 → down lab ×2 都成功，退出码 0
```

## 补充：状态墙增量刷新（已实现）

- 每个抽屉一行控件缓存到 `_cells`，刷新时只改颜色/文字/ToolTip
- 新抽屉追加、消失的抽屉移除，不再 `Children.Clear()`
- `_refreshing` 防止两次刷新叠加

验证：状态墙显示「1 个抽屉 · 正常 1 · 运行 0 · 异常 0」，动作后刷新无整表闪烁。
