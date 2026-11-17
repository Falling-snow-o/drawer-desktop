# Drawer Desktop

> 现状：管理器是 **C# / WPF**（`gui\`），引擎是 `box.ps1`。
> 安装包：`dist\drawer-setup.exe`（自解压，装到 `%LOCALAPPDATA%\Drawer`）。
> 卸载：`drawer-setup.exe --uninstall`。

> 把 WSL 从"微软管理的发行版"变成"你管理的文件夹"。
> 零安装、只占一个目录 + 一个注册表项、删掉即卸载。

当前版本 **0.9.0**（`box.ps1 version` 可查）。

---

## 图形界面（主界面）

双击桌面 `boxrun`（= `boxrun.exe`，带图标、无控制台窗口）打开管理器：

![boxrun 管理器](docs/gui.png)

一个窗口管全部：选抽屉、看状态、**启动 / 停止 / 终端 / 图形界面 / 恢复初始 / 快照 / 自检 / 新建 / 删除**。
界面只做调度和展示，底层仍然调用 `box.ps1`（唯一的事实来源），命令行随时可用。`box.ps1 gui lab -y` 是不弹确认的版本。

- 右上角显示**抽屉数量**（`共 N 个`），下拉框切换；每 12 秒自动刷新，也可以按「刷新」
- 「新建」弹对话框：名字 + CPU/内存/进程上限，**预填按本机算的建议值，可改，超标会被拦**
- 「终端」开一个连进抽屉的 Windows 控制台
- 「添加抽屉」= 选一个目录（可指向任意位置），可选本地 rootfs 文件，添加后可直接构建
- 「工具箱」= 读 `catalog.json`：勾选后直接清理 / 安装 / 装插件
- 「图形界面」= `box.ps1 gui`：开**文件管理器**（pcmanfm），窗口直接出现在桌面上；箱内没有时自动安装
- 「桌面」= `box.ps1 desktop`：开**完整桌面**（xfce4），首次自动装约 400 MB；桌面包在**一个窗口**里（Xephyr 嵌套 X），不是散落的宿主窗口
- 「恢复初始」= `box.ps1 restore`，清空箱内改动（软件、配置），保留 `data/`
- 「删除」会二次确认，然后注销发行版（vhdx 一起删）+ 删整个抽屉目录（**含 `data/`**）
- 未构建的抽屉显示 `△ 未构建`，启动按钮是灰的
- **关掉窗口会自动停止当前抽屉**（等同点「停止」），不会把虚拟机和内存留在后台
- 底栏有「**空闲 5 分钟后自动停止**」开关（默认开）：5 分钟没操作就自动 down，释放 vmmemWSL`n- 抽屉**空闲约 1 分钟会被 WSL 自动回收**（不保活、省内存），底栏有提示；点「启动」或执行 `exec` 会重新拉起

---

## 安装

两种形态，产物都在 `dist\`：

| 文件 | 体积 | 用法 |
|---|---|---|
| `boxrun-setup-v0.9.0.exe` | ~400 KB | **双击**，提权 → 选目录 → 全自动 |
| `boxrun-setup-v0.9.0.zip` | ~190 KB | 解压后右键以管理员运行 `安装.cmd` |

> 打包脚本（`打包.ps1` / `make-icon.ps1`）不随这个开发目录分发，发布包里才有。
> 只有本目录时，直接跑 `powershell -ExecutionPolicy Bypass -File Setup.ps1` 即可。

### 重复安装

**已经装过的话，双击会先问你怎么处理：**

```
检测到已安装的 boxrun

    安装位置：D:\tools\boxrun
    版本：0.9.0
    抽屉数据：D:\tools\boxes

是否先删除旧版本？

    是    —— 删除旧版本后重新安装到原位置（boxes\ 里的数据保留）
    否    —— 不删除，选一个新位置安装
    取消  —— 退出
```

- **是** → 静默卸载旧版（只删程序，`boxes\` 不动），然后原地重装
- **否** → 弹目录选择框，装到别处（旧版本原样保留，两套并存）
- **取消** → 什么都不做

选完位置后还有一道**二次确认**：如果目标目录里已经有一个 `box.ps1`（说明那儿也是 boxrun），会再问一次才覆盖。

卸载旧版用的是刚解压的新 `Setup.ps1 -Uninstall -Silent`，所以清理逻辑总是最新的一份，不依赖旧安装目录里留着什么。

### 安装流程

```
1. 双击 exe   → 立刻弹 UAC（清单是 requireAdministrator）
2. 选目录     → 弹出文件夹选择框，自己挑位置（记忆上次选择）
3. 检测环境   Windows 版本 / BIOS 虚拟化 / SLAT / 虚拟机平台 /
              HypervisorPlatform / WSL / Hypervisor 是否运行 / 磁盘 / GPU
4. 判定      拆成「阻塞项」（需人工）和「可自动修复项」
5. 修复      dism 启用功能 · wsl --install · bcdedit 打开 hypervisor
6. 需要重启  自动登记 RunOnce，重启登录后继续，不用你记
7. 部署      程序装到 <你选的目录>\boxrun，数据在 <你选的目录>\boxes
8. 登记      写入"设置 → 应用 → 已安装的应用"，加开始菜单快捷方式
9. 建抽屉    可选，直接创建 lab
```

**安装位置自己选**，默认 `%USERPROFILE%\boxrun`。选完之后：
- 程序 → `<你选的位置>\boxrun\`
- 抽屉 → `<你选的位置>\boxes\lab\`

选过一次之后会记住，下次升级默认就是它。

只想看检测结果、不改系统：

```powershell
powershell -ExecutionPolicy Bypass -File Setup.ps1 -Check
```

### 卸载（三个入口，任选其一）

| 入口 | 位置 |
|---|---|
| **设置 → 应用 → 已安装的应用 → boxrun → 卸载** | 最标准 |
| **开始菜单 → boxrun → 卸载 boxrun** | 最直接 |
| **`boxrun-setup-v0.9.0.exe --uninstall`** | 安装包不在了也能用 |

卸载做的事：

```
注销所有抽屉发行版 → 删程序目录 → 清 PATH
→ 删"已安装的应用"登记 → 删开始菜单快捷方式
→ 询问是否删 boxes\（默认保留，data/ 在里面）
```

**不会**回退 Windows 功能（虚拟机平台等）——那是系统级改动，留给你决定：

```powershell
dism /online /Disable-Feature /FeatureName:VirtualMachinePlatform
dism /online /Disable-Feature /FeatureName:HypervisorPlatform
bcdedit /set hypervisorlaunchtype off
```

---

## 本机当前状态（2026-11-11 复核）

**结论：WSL2 已经能起来，`lab` 已经注册，可以正常 `up` / `exec` 了。**

| 检查项 | 2026-11-10 | 2026-11-11 复核 |
|---|---|---|
| `HvHost` 服务 | Stopped | **Running** |
| VMware 进程（vmnat / vmware-authd） | 在跑，占 VT-x | **不在** |
| `lab` 发行版 | 未注册 | **已注册**，BasePath `D:\Acta\boxes\lab\state`，v2 |
| `ext4.vhdx` | 无 | **153 MB**（11-11 10:11） |
| `HypervisorPresent` | False | 需在普通终端复核：`(Get-CimInstance Win32_ComputerSystem).HypervisorPresent` |

2026-11-11 端到端实测（`up` → `exec` → `status` → `down` 全跑通）：

- `status` 的运行判定已修：未运行时显示 `○ 已停止`，运行中才 `● 运行中`
- `data/` ↔ `/work` 双向可见（Windows 写一个文件，箱内 `cat` 得到；反之亦然）
- 卸掉 `/work` 后再 `exec`，`boxrun-exec` 会自动补挂
- 箱内 `cgroup.controllers` = `cpuset cpu io memory hugetlb pids rdma`（memory/cpu 在）
- 箱内 `/dev/dxg` 存在、`/usr/lib/wsl/lib/libcuda.so*` 齐全
- `/etc/wsl.conf` 里 interop、automount 两处 `enabled=false` 生效
- **关掉 interop 后 WSLg 仍然可用**：`/mnt/wslg` 在、`/tmp/.X11-unix/X0` 在、
  `DISPLAY=:0` 下 `xeyes` 能连上并常驻（架构地基验证通过）
- `box.ps1 gui lab xclock -digital` 实测：窗口树里有 `"xclock" (233x35)`，进程在箱内
- **显存闸实测**：无闸对照 8×256 MiB 全通过；`BOXRUN_VRAM_MB=512` 时第 3 次返 `r=2`；
  1024 时第 5 次返 `r=2`
- `down` 正常 `sync` → `terminate` → 撤锚点，`data/` 未被动过

当初的根因（VMware 关掉了 `hypervisorlaunchtype`）已随环境变更消失，修复步骤保留在
`PITFALLS.md` 0.1 里备查。

> 注意：**不要在 DSH 这类受限沙箱里跑 `box.ps1`**。沙箱里 `wsl.exe` 会返回
> `Wsl/E_ACCESSDENIED`、WMI 会拒绝访问，会被误判成环境坏了。用普通 PowerShell 窗口。

---

## 它是什么

不是一个软件，是三样东西的组合：

```
一个文件夹（掌管状态） + 一份 box.yaml（记录约定） + 一个 PowerShell 脚本（当解释器）
```

自研只有三件事，其余全是别人的：

| 能力 | 谁提供 |
|---|---|
| 内核 / namespace / cgroup | WSL2 + Linux |
| GPU 直通（CUDA） | WSL2（dxgkrnl） |
| 磁盘 / 分层 / 快照 | WSL 的 vhdx |
| rootfs 打包格式 | OCI / tar |
| 生命周期命令语义 | 借 compose 的动词 |
| **编排顺序** | **本项目** |
| **资源账本** | **本项目** |
| **便携语义** | **本项目** |

---

## 输出约定

所有命令的输出都长这样：

```nboxrun · 启动 lab
----------------------------------------------

▸ 同步 guest 脚本
▸ 应用配额
  ✓ 配额已应用：4 核 / 内存 6G / 进程 512
▸ 挂载 data → /work
  ✓ data → /work，downloads → /downloads 已挂载
  ✓ lab 已就绪
```n
- ▸ 步骤，✓ 成功，! 警告，✗ 失败，缩进 4 格的是细节
- 出错只打一行原因 + 一句提示，不再抛 PowerShell 堆栈；要看位置设 BOXRUN_DEBUG=1`n
## 命令

```
box.ps1 init <name>          创建抽屉（配额默认按本机算，可加 -cpu/-memory/-pids）
box.ps1 add <目录> [-Name 名] [-Image 本地rootfs.tar.gz]
                             把任意目录登记成抽屉，位置不限于 boxes\\
box.ps1 api list|info|catalog   JSON 接口（界面和外部脚本只依赖它）
box.ps1 build <name>         下载 rootfs → wsl --import → 加固隔离
box.ps1 up <name>            启动 + 同步 guest 脚本 + cgroup 配额 + 挂载 data + 起电源锚点
box.ps1 exec <name> [cmd]    在抽屉里执行（默认 bash），进 cgroup、按需补挂 data
box.ps1 gui <name> [cmd]     在 Windows 桌面开图形窗口（默认 pcmanfm 文件管理器）`nbox.ps1 desktop <name> [-y]  开完整桌面（xfce4，装在一个窗口里，首次约 400 MB）
box.ps1 status <name>        资源账本（运行中才能看到真实配额占用）
box.ps1 ps <name>            status 的别名
box.ps1 down <name>          sync → terminate → 撤锚点
box.ps1 restore <name> [-y] [-KeepGui] [-CacheOnly]
                             恢复初始：默认全清（保留 data/ 和 downloads/）
                             -KeepGui 重建后自动装回桌面；-CacheOnly 只清缓存
box.ps1 clean <name>         只清缓存（apt/tmp/pip/npm/journal）
box.ps1 snap <name> <tag>    全量快照
box.ps1 remove <name> [-y]   删除抽屉（注销发行版 + 删目录，含 data/）
box.ps1 list                 列出抽屉（JSON，给界面用）
box.ps1 doctor               自检
box.ps1 link <name>          重建"图形界面"入口（.cmd + .lnk）
box.ps1 menu                 交互菜单
box.ps1 version              打印版本
```

第一次：

```powershell
cd D:\Acta\boxrun
.\box.ps1 init lab
.\box.ps1 build lab
.\box.ps1 up lab
.\box.ps1 exec lab bash
```

`status` 里"运行中"的判定用的是 `wsl -l --running`（`wsl -l -q` 只表示**已注册**，
不代表在跑）。`data/` 的挂载状态单独一行显示。

---

## 图形界面：窗口在 Windows，进程在抽屉

抽屉是纯命令行的 Linux，**不需要装桌面环境**也能跑图形程序，靠的是 WSLg：
箱内进程通过 Wayland/X 协议画到一个合成器上，Windows 用 RDP 把**每个应用变成
一个独立的 Windows 窗口**。所以是"宿主机出桌面，抽屉出算力"。

```
box.ps1 gui lab xclock -digital      # 开窗口，不占终端
box.ps1 exec lab python3 plot.py     # 前台跑，看输出；需要窗口也行
```

`gui` 做的事：注入 `DISPLAY=:0` / `WAYLAND_DISPLAY=wayland-0`，`nohup` 后台启动，
1 秒后确认进程还活着，然后告诉你 PID。关窗口 = 进程结束，日志在 `/tmp/boxrun-gui.log`。

已验证（2026-11-11，interop 关着）：

```
xwininfo -root -tree
  0x60000a "xeyes":  ("xeyes" "XEyes")    2548x1567+6+27
  0x60000b "xclock": ("xclock" "XClock")   233x35+38+59
```

窗口真的建出来了，进程在箱内（`ps` 可见），窗口在 Windows 桌面。

几点说明：

- **不用装 X server、不用装 xfce**。装了反而多一层，纯浪费。
- 想装什么就直接 `apt install`，`x11-apps`、`xterm`、`firefox` 都能直接出窗口。
- GPU 图形走 WSL2 的 `/dev/dxg` + D3D12，箱内的 `libGL` 是 Mesa 的 d3d12 后端；
  要验证可以 `apt install mesa-utils` 后 `gui lab glxinfo -B`。
- 想要"整个桌面"这种用法也能做（`apt install xfce4` + `gui lab startxfce4`），
  但那会变成一个大窗口套小窗口，日常没必要。

### 一键打开图形界面

抽屉目录里的入口：

| 入口 | 位置 / 用法 | 说明 |
|---|---|---|
| `启动.lnk` | `D:\Acta\boxes\lab\` | 打开**管理器**（本页开头那个窗口） |
| 菜单 `7` | `.\box.ps1 menu` | 已经进了命令行菜单时用 |
| 命令 | `.\box.ps1 gui lab` | 不带程序名 = pcmanfm 打开 `/` |

第一次会问要不要装 pcmanfm（约 40 MB），装过就不再问。入口丢了用
`.\box.ps1 link lab` 重建。

### 看抽屉里的文件，三种方式

**① 资源管理器直接进（零安装，日常最省事）**

地址栏输入：

```
\\wsl.localhost\lab\
```

（老系统用 `\\wsl$\lab\`）整个 Linux 根目录可读写，双击打开、拖拽复制都行。实测可用。

**② 箱内文件管理器（要有"Linux 桌面"的观感就用这个）**

```powershell
.\box.ps1 exec lab apt install -y pcmanfm
.\box.ps1 gui lab pcmanfm /work    # 打开 Windows 的 data 目录
.\box.ps1 gui lab pcmanfm /        # 打开 Linux 根目录
```

PCManFM 窗口出现在 Windows 桌面，右键菜单、拖拽、复制粘贴都能用。

**③ 整套桌面（可选，比较重）**

```powershell
.\box.ps1 exec lab apt install -y xfce4 xfce4-terminal
.\box.ps1 gui lab startxfce4
```

等 5–10 秒，桌面会作为一个**窗口**出现：自带面板、文件管理器、终端。
和 ② 的差别只是"多了个壳"，文件还是同一份。

> 提示：GTK 程序偶尔在 Wayland 下不显示窗口，加 `env GDK_BACKEND=x11` 强制走 X11：
> `.\box.ps1 gui lab env GDK_BACKEND=x11 pcmanfm /`

---

## 目录结构

```
D:\Acta\
├── boxrun\
│   ├── box.ps1              ← 解释器（唯一自研逻辑）
│   ├── BoxRun.Gui.ps1       ← 图形管理器（WPF，主界面）
│   ├── boxrun-gui.vbs       ← 双击开界面（走 WMI，无控制台）
│   ├── Setup.ps1            ← 安装器 / 检测 / 修复 / 卸载
│   ├── 安装.cmd、卸载.cmd    ← 双击入口（自动提权）
│   ├── README.md
│   ├── PITFALLS.md          ← 踩坑清单，比代码值钱
│   ├── docs\gui.png         ← 界面截图
│   ├── vram\
│   │   ├── boxrun-vram.c    ← 显存闸（LD_PRELOAD）
│   │   └── test-vram.c      ← 闸门的验证程序
│   └── examples\
│       └── box.yaml         ← 配置模板
└── boxes\
    └── lab\
        ├── box.yaml         ← 你这个抽屉的配置
        ├── blobs\           ← rootfs（28.6 MB）
        ├── state\           ← WSL 独占，unregister 会删这里
        ├── data\            ← 你的资产，挂成箱内 /work
        └── 启动.lnk         ← 双击打开管理器（图形界面在界面里点）
```

**硬性约束**：`data/` 必须在 `state/` 之外，否则 `wsl --unregister` 会连它一起删。
`box.ps1 doctor` 会检查这一条，也会检查注册状态和 `data/` 可写。

### downloads/ —— 给安装包和下载文件留的位置

每个抽屉都有 downloads\，挂到箱内 /downloads，和 data/ 一样双向可见：

```nD:\\Acta\\boxes\\lab\\downloads\\   <->   /downloads```n
把 .run 安装包、数据集、离线包丢进去，箱内直接 cd /downloads 就能用；恢复初始 也不会删它。

### data/ 怎么进抽屉

`automount` 是关掉的（隔离要求），所以 Windows 盘不会自动出现。boxrun 的做法是
**只挂这一个目录**：

```
up   → 把 data 绝对路径 base64 写进箱内 /etc/boxrun/work.src
     → boxrun-work → mount -t drvfs <data> <target>
exec → boxrun-exec 发现没挂，自动补挂一次
```

路径走**文件**而不是命令行，是因为 `wsl.exe` 会把 argv 里的反斜杠吃掉
（`D:\Acta\x` 到箱内变成 `D:Actax`，见 `PITFALLS.md` 0.7）。

抽屉被空闲回收后挂载会丢，所以 `exec` 里做了幂等补挂；`status` 会显示
`数据挂载 ✓ 已挂载 / ✗ 未挂载`。

### 显存闸（gpu.vram）

`gpu.vram: 0` → 不限制；`gpu.vram: N`（MiB）→ `up` 时在箱内编译
`vram\boxrun-vram.c` 成 `LD_PRELOAD` 闸门，**累计申请超过 N MiB 就返回
`CUDA_ERROR_OUT_OF_MEMORY`**，让框架自己走它的 OOM 分支，而不是把整卡吃满。

```
up   → 检查 gcc（缺了就 apt 装）→ 编译 /usr/local/lib/boxrun-vram.so
     → 写 /etc/boxrun/vram.env（BOXRUN_VRAM_MB + LD_PRELOAD）
exec → boxrun-exec source 这个文件，再把命令 exec 掉
```

边界要说清楚：

- 只覆盖**通过 `box.ps1 exec` 启动的进程**；直接 `wsl -d lab` 进去跑的不管。
- 拦的是 `cuMemAlloc / cuMemAlloc_v2 / cuMemAllocManaged / cuMemAllocAsync /
  cuMemAllocPitch`，**不拦** `cuMemCreate`（VMM 预留，拦了会误伤）。
- 这是进程内软闸，不是 MIG。GeForce 全系没有硬件切分，别指望它防住驱动内部池。

### CPU / 内存 / 进程上限，限制的是谁

`box.yaml` 里的 `quota` 用 cgroup v2 在**抽屉内部**生效：

| 字段 | 写法 | 实际含义 |
|---|---|---|
| `cpu` | `400000 100000` | 每 100 ms 最多用 400 ms CPU 时间 = **4 核**（`配额/周期`） |
| `memory` | `12G` | 抽屉内这些进程总共最多 12 GiB |
| `pids` | `512` | 最多 512 个进程/线程，防 fork 炸弹 |

必须分清两件事：

1. **它不会限制 Windows。** 配额是"抽屉最多能用多少"，不是"从系统里划走多少"。
   空闲时抽屉几乎不占资源；但抽屉跑满时，确实会吃掉本机对应的 CPU 和内存。
2. **只有通过 `box.ps1 exec` 启动的进程会进这个 cgroup。** systemd 自己拉的服务不在里面，
   所以「内存 0 / 12 GB」在空闲时是正常的——不是没生效。

> **默认值按本机自动算**（`init` / 界面「新建」时）：CPU 取逻辑核的 1/4（最多 8 核），
> 内存取总内存的 40%（最多 8G，且至少给系统留 4G），进程 512。
> 这台机器（20 逻辑核 / 15.4 GB）算出来是 **5 核 / 6 GB / 512**。
>
> 创建时可以直接改：
>
> ```powershell
> .\box.ps1 init lab2 -cpu 2 -memory 3G -pids 256   # 命令行
> ```
>
> 界面里点「新建」会弹对话框，三个值都预填建议值、可以改；超出本机规格会拦住。
> 已建好的抽屉改 `boxes\<名字>\box.yaml` 的 `quota`，下次 `up` 生效。

---

## 它占用/改变电脑的什么

| 层 | 对象 | 可撤销 |
|---|---|---|
| 磁盘 | `boxes\<name>\` 目录（10–30 G 动态） | ✅ 删目录 |
| 注册表 | `HKCU\...\Lxss` 一项 | ✅ `wsl --unregister` |
| 进程 | `vmmemWSL` / `wsl.exe` / 锚点 PowerShell | ✅ 进程退出即消失 |
| 内核 | cgroup 目录 `/sys/fs/cgroup/boxrun` | ✅ `wsl --shutdown` 归零 |
| 挂载 | 箱内 `/work`（只此一个 Windows 目录） | ✅ `down` / 退出即消失 |
| 全局配置 | `.wslconfig` **不动** | — |
| 电源计划 | **不动**（用 `SetThreadExecutionState` 声明） | — |
| 服务 / 驱动 | **不装** | — |

**唯一会碰系统行为的开关**是 `power.keep_awake`，而它用"声明"而不是"设置"：
进程活着时系统不睡，进程死了声明自动失效。

### 完全卸载

```powershell
cd D:\Acta\boxrun
.\box.ps1 down lab
wsl --unregister lab
Remove-Item -Recurse -Force D:\Acta\boxes\lab
```

三步，没有第四步。

---

## 输出约定

所有命令的输出都长这样：

```nboxrun · 启动 lab
----------------------------------------------

▸ 同步 guest 脚本
▸ 应用配额
  ✓ 配额已应用：4 核 / 内存 6G / 进程 512
▸ 挂载 data → /work
  ✓ data → /work，downloads → /downloads 已挂载
  ✓ lab 已就绪
```n
- ▸ 步骤，✓ 成功，! 警告，✗ 失败，缩进 4 格的是细节
- 出错只打一行原因 + 一句提示，不再抛 PowerShell 堆栈；要看位置设 BOXRUN_DEBUG=1`n
## 命令行菜单（不想开窗口时）

把 `examples\box.yaml` 换成抽屉目录里的 `启动.lnk` 双击，出菜单：

```
lab  ·  boxrun
--------------------------------------------------
  状态        ● 运行中
  根盘        6.2 GB
  数据        1.4 GB  →  /work
  显存闸      4096 MiB  （LD_PRELOAD，只拦 exec 起的进程）
  内存配额    3.1 / 12.0 GB  (26%)
  CPU 配额    400000 100000
  进程        18 / 512
  内核        6.6.87.2-1
  已运行      2 天 4 小时
  GPU 直通    ✓ /dev/dxg   ✓ libcuda
  数据挂载    ✓ 已挂载   /work
  显存(全局)  2412 / 8188 MiB    GPU 3%
--------------------------------------------------
  [1] 进入终端    [2] 启动    [3] 停止
  [4] 回滚        [5] 自检    [7] 图形界面    [0] 退出
```

---

## 下一步

1. 日常用法：`box.ps1 up lab` → `box.ps1 exec lab bash` → `box.ps1 down lab`
2. 图形程序：`box.ps1 gui lab <程序>`，窗口在 Windows 桌面，进程在抽屉里
3. 显存闸按需调：`gpu.vram: 0` 关掉，或改小到 2048 之类；改完下次 `up` 生效。
   注意它只管 `exec` 起的进程（见「显存闸」一节）。
4. 想验证 GPU 真实可用：`box.ps1 exec lab bash` 进去后装 CUDA toolkit 跑个 kernel，
   别装驱动（`PITFALLS 1.4`）。
5. 换机器时把整个 `D:\Acta` 目录拷走即可；新机器上要 `wsl --unregister lab` 再 `build`
   （vhdx 带不过去，`data/` 里的东西不受影响）。

---

## 工程、许可与支持

- 许可证：[LICENSE](LICENSE)（MIT）
- 第三方组件：[THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md)
- 安全模型与边界：[SECURITY.md](SECURITY.md)

### 测试

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File test\smoke.ps1      # 引擎
powershell -NoProfile -ExecutionPolicy Bypass -File test\gui-smoke.ps1  # 界面（需已安装并运行）
powershell -NoProfile -ExecutionPolicy Bypass -File test\run-all.ps1    # 两套一起
powershell -NoProfile -ExecutionPolicy Bypass -File test\ci.ps1         # 语法 + 编译
```

### 诊断包

面板 → **导出诊断包…**，会在桌面生成 `drawer-diagnostics-<时间>.zip`，包含：

- 最近的日志（14 天内、按天）
- `settings.json` / `boxes.json` / `tags.json` / `aliases.json`
- 每个抽屉的 `box.yaml`
- 应用版本、系统版本、WSL 版本、`doctor` 输出

### 配置版本

`settings.json` 带 `version: 1`；保存设置时会保留未知字段，方便以后升级。
`box.yaml` 模板带 `schema: 1`，引擎对未知字段容忍。

## 发布、更新与回滚

### 签名

```powershell
# 用证书指纹（CurrentUser\My 里的代码签名证书）
powershell -File 打包.ps1 -Version 1.1.0 -Sign -CertThumbprint <SHA1指纹>
```

- 自签名证书只能做本地验证（`Get-AuthenticodeSignature` 状态会是 `UnknownError`）
- 对外发布需要受信任的代码签名证书；签名不会自动加时间戳
- 未提供 `-Sign` 时仍可打包，但 Windows 会提示未知发布者

### 更新清单

打包会生成 `dist\latest.json`：

```json
{ "version": "1.1.0", "url": "https://…/drawer-setup.exe", "sha256": "…", "notes": "…" }
```

- 本地测试时 `url` 可以直接是 `D:\…\drawer-setup.exe` 或 `file:///…`
- 设置里的「更新源」填 `latest.json` 的路径/URL
- 流程：下载 → sha256 校验 → 启动安装器 `--quiet --restart` → 安装器停进程、备份、覆盖、重启

### 回滚

安装器覆盖安装前会把当前目录备份到 `%LOCALAPPDATA%\Drawer.backup`：

```powershell
& "$env:LOCALAPPDATA\Drawer\drawer-setup.exe" --rollback --quiet
```

回滚会停掉进程、用备份覆盖、再启动应用。

### 崩溃报告

- 未处理异常写到 `%USERPROFILE%\.boxrun\crashes\crash-*.txt`
- 设置里填「崩溃上报地址」后，会额外 POST 一份纯文本到该地址
- 「导出诊断包」会自动带上 crashes 目录

### CI

- 托管 runner：`.github/workflows/ci.yml` 跑语法检查、编译、打包（跳过 WSL 冒烟）
- 本地完整回归：`test\smoke.ps1`、`test\collab-smoke.ps1`、`test\gui-smoke.ps1`
