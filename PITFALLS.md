# 踩坑清单

> 这份文件比代码值钱。代码能重写，坑记不住。
> 每条都标注了**是否在本机实测过**。

---

## 0. 本机实测发现（2026-11-10）

### 0.1 WSL2 整个跑不起来 —— VMware 占了 VT-x

**状态：本机已消失（2026-11-11 复核，见 README「本机当前状态」）**

```
wsl --import → 错误代码: Wsl/Service/RegisterDistro/CreateVm/HCS/HCS_E_HYPERV_NOT_INSTALLED
```

诊断证据链：

| 项 | 值 | 含义 |
|---|---|---|
| `Win32_Processor.VirtualizationFirmwareEnabled` | `True` | BIOS 里 VT-x 是开的 |
| `Win32_ComputerSystem.HypervisorPresent` | **`False`** | **Windows hypervisor 没运行** |
| `HvHost` 服务 | `Stopped` | 同上 |
| `HKLM:\SYSTEM\CurrentControlSet\Services\WinHvPlatformHost` | **缺失** | WHPX 功能未启用 |
| VMware | `17.6.2` 在 `D:\vmware_pro`，服务全在跑 | 占用 VT-x |
| `hvix64.exe` / `vmcompute.exe` / `vmwp.exe` | 全存在 | 二进制没缺，只是没启动 |

**教训**：`wsl -l -v` 显示 `docker-desktop 2` **不代表 WSL2 可用** ——
那只是注册表记录。判断真实可用性只看一条：

```powershell
(Get-CimInstance Win32_ComputerSystem).HypervisorPresent   # 必须是 True
```

修复见 `README.md`。VMware 17.6.2 支持共存，不用二选一。

> 2026-11-11 复核：`HvHost` 已 Running、VMware 进程不在、`lab` 已注册、`ext4.vhdx` 153 MB，
> 说明 import 已经成功过。旧记录里的 `D:\dsh-deepseek\Acta` 是搬目录之前的路径。

### 0.2 PowerShell 5.1 读无 BOM 的 UTF-8 脚本会整片乱码

**状态：实测遇到**

现象：`Parser::ParseFile` 报 64 个语法错误，错误信息本身是乱码
（`意外的标记"缂哄皯閰嶇疆鏂囦欢:"`）。原因是文件写成 UTF-8 无 BOM，
Windows PowerShell 5.1 按 GBK 读。

处理：写完后强制加 BOM。

```powershell
$c = [IO.File]::ReadAllText($f, [Text.UTF8Encoding]::new($false))
[IO.File]::WriteAllText($f, $c, [Text.UTF8Encoding]::new($true))
```

**连带影响**：任何 `edit` 之后都要重新检查 BOM 是否还在。

### 0.3 `wsl.exe` 输出是 UTF-16，管道里会变成 `W S L   版本`

**状态：实测遇到**

修复：设 `$env:WSL_UTF8 = '1'`（WSL 2.x 官方支持），脚本第一行就设。

### 0.4 `wsl -l -q` 是「已注册」，不是「正在运行」

**状态：实测遇到，0.5.0 已修**

`status` 原来用 `Get-DistroList`（即 `wsl -l -q`）判断运行状态，于是只要构建过就
永远显示 `● 运行中`，`down` 之后也不变。

判定必须用 `wsl -l --running -q`；老版本 WSL 没有这个开关时退化为解析
`wsl -l -v` 的 STATE 列（`Running` / `运行中`）。

### 0.5 `automount` 关掉后，`data/` 不会自己出现

**状态：实测，0.5.0 已实现**

`[automount] enabled=false` 是隔离的地基，但代价是 Windows 目录也不再自动挂进来。
`store.type: bind` 以前只是 `up` 时打印一行"数据目录 → /work"，实际什么都没挂。

正确做法是在箱内显式挂**只这一个目录**：

```bash
mount -t drvfs '<Windows 绝对路径>' /work -o metadata,uid=0,gid=0,umask=022
```

两个必须注意的点：

- 挂载会随发行版终止而消失（空闲回收、`wsl --shutdown`），所以 `exec` 里要幂等补挂；
- 路径别走 `env`/命令行传进去，会被 `wsl.exe` 吃掉反斜杠（见 0.7），要写文件；
- 不要为了省事去开 `automount` 或挂整盘，那等于把宿主文件全暴露给抽屉。

### 0.6 在受限沙箱里跑 `wsl.exe` 会得到 `Wsl/E_ACCESSDENIED`

**状态：实测（DSH 的 workspace-write 沙箱）**

同一个会话里：

| 命令 | 结果 |
|---|---|
| `wsl.exe -l -v` | `拒绝访问。错误代码: Wsl/E_ACCESSDENIED` |
| `Get-CimInstance Win32_ComputerSystem` | `拒绝访问`（0x80041003） |
| `bcdedit /enum` | `The boot configuration data store could not be opened. Access is denied.` |

**这不是环境坏了**，是沙箱挡住了 HCS 通道和 WMI。诊断和运行 boxrun 都要用普通
PowerShell 窗口；在沙箱里跑只会得到假阴性。

（顺带：`HvHost` 服务状态、注册表 `Lxss`、文件大小这些不经过 HCS，沙箱里仍可读，
所以能用它们做旁证。）

### 0.7 `wsl.exe` 会吃掉 argv 里的反斜杠

**状态：实测确认（2026-11-11），已改走文件传递**

```powershell
wsl -d lab -u root -- env 'FOO=D:\Acta\boxes\lab\data' printenv FOO
# 输出：D:Actaboxeslabdata
```

第一次实现 bind 挂载就栽在这里：`env BOXRUN_DATA=D:\Acta\...\data` 进箱后变成
`D:Actaboxeslabdata`，`mount -t drvfs` 直接报"挂载失败"，但错误信息看起来像路径写错了。

对策：Windows 路径用 base64 写进箱内文件（`Set-GuestFile`），箱内 `cat` 出来再用。
**任何要穿过 `wsl.exe` 命令行的 Windows 路径都按这个处理**，别指望引号能救。

### 0.8 在非交互宿主里 `Read-Host` 会直接抛错

**状态：实测（GUI 调用时踩到）**

界面点「图形界面」→ 箱内缺 pcmanfm → `box.ps1 gui` 走到 `Read-Host "现在安装？"`，
但调用方是 runspace，没有交互宿主，于是直接报：
`主机程序或命令类型不支持用户交互`。

对策：`gui` 支持 `-y`（不问、直接装），界面固定传 `-y`；命令行不带 `-y` 时仍然交互确认。
**任何会被 GUI 调用的命令都不该依赖 `Read-Host`。**

---

## 1. WSL 的坑

### 1.1 `wsl --terminate` ≠ 关机

**状态：已知，未实测**

`--terminate` 只停一个发行版，共享的轻量 VM 可能还在跑，资源没释放。
要真正关掉用 `wsl --shutdown`。

### 1.2 `vmIdleTimeout` 默认 60 秒会杀掉服务

**状态：实测确认（systemd 也挡不住）**

最后一个 Linux 进程退出后约 60 秒，VM 自动关闭——即使 `[boot] systemd=true`、PID 1 是 systemd，
实测 `up` 之后 75 秒发行版就被回收了。

**决策：不保活。** 保活需要在 Windows 侧常驻一个 `wsl ... sleep` 进程，代价是白占内存；
现在的做法是 `exec` / 「启动」按需拉起，界面底栏明确写"空闲约 1 分钟会被 WSL 自动回收"。

**不通过改 `.wslconfig` 解决**（那是全局的，会波及 docker-desktop）。

0.9.0 起 `down` 会顺手处理：terminate 之后如果 `wsl -l --running` 已经没有别的发行版，
就直接 `wsl --shutdown`，把 `vmmemWSL` 的内存也放掉；如果还有别的发行版在跑则保留 VM。

### 1.3 `wsl --unregister` 会连 vhdx 一起删

**状态：已知，未实测**

所以 `data/` 绝不能放在 `state/` 下面。
`box.ps1 doctor` 第 8 项检查这个。

### 1.4 别在抽屉里装 NVIDIA 驱动

**状态：已知，未实测**

WSL2 的 CUDA 库由宿主驱动通过 `/usr/lib/wsl/lib` 提供。
在箱内 `apt install nvidia-driver-*` 或跑 `.run` 安装包会覆盖它，CUDA 立刻失效。
只装 CUDA Toolkit，永远不装驱动。

### 1.5 关了 interop，WSLg 图形还能用

**状态：实测通过（2026-11-11）**

`[interop] enabled=false` 只断掉 `.exe` 调用通路。
WSLg 走的是独立的 RDP 通道，不受影响——实测 `X0` socket 在，`xeyes` / `xclock` / `pcmanfm`
都能出窗口，而箱内 `cmd.exe` 确实找不到。

### 1.6 发行版重启后 cgroup 配额会静默消失

**状态：实测遇到，0.7.0 已自愈**

`/sys/fs/cgroup/boxrun` 是 `up` 时在箱内建的，`wsl --terminate` 或空闲回收后整个目录没了，
配额悄悄失效，但 `status` 只会显示 `0 / 12 GB`，看起来像"没在跑"。

现在：`up` 把配额写进 `/etc/boxrun/quota.env`，`boxrun-exec` 发现 cgroup 不在就重建，
`boxrun-status` 会报 `cg_present=no`，界面显示「未生效」。

验证：

```powershell
wsl --terminate lab
.\box.ps1 exec lab true
# 之后 cpu.max 仍是 400000 100000 / memory.max 12884901888 / pids.max 512
```

---

## 2. 磁盘与分层的坑

### 2.1 卸载 vhdx 前必须 sync

**状态：已知，未实测**

写回缓存分两层（WSL 一层、Windows 一层）。少一次 `sync` 就是一次 ext4 损坏，
而差分盘损坏**没有修复手段**，只能删掉重来。

`box.ps1 down` 里 `sync` 是第一步。

### 2.2 差分盘父子链不能断

**状态：已知（本版未采用差分盘）**

父盘改名 / 移动 = 整条链报废，里面的环境全丢。
`base.vhdx` 一旦生成就只读、只许 copy 不许 move。

### 2.3 跨机器必须 Merge-VHD

**状态：已知（本版未采用差分盘）**

带差分层 export 到另一台机器打不开，要先 `Merge-VHD -Destination merged.vhdx` 拍平。

### 2.4 `/mnt` 下跑项目会慢 10–50 倍

**状态：已知，未实测**

9p 协议跨文件系统小文件 IO 极慢：

| 操作 | ext4（箱内） | `/mnt/d`（Windows 盘） |
|---|---|---|
| `git status` | 0.1 s | 30 s |
| `npm install` | 20 s | 10 分钟 |

对策：代码放箱内 `~/` 用 git 同步；`data/` 只放大文件（数据集、权重、产物）。

---

## 3. 网络的坑

### 3.1 `mirrored` 模式下 3389 会和宿主 RDP 撞车

**状态：已知，未实测**

mirrored 让 WSL 和 Windows 共享端口空间，而 Windows Pro 自带的远程桌面也占 3389。
本版默认 `NAT`，不碰 mirrored。

### 3.2 `portproxy` 规则是持久的

**状态：实测确认（当前 0 条，干净）**

`netsh interface portproxy add` 的规则重启后仍在，不受任何进程生命周期管理。
本版默认 `net.publish: []`，一条都不建。
`box.ps1 doctor` 第 4 项对账。

### 3.3 Windows 访问箱内服务不需要 portproxy

**状态：已知，未实测**

NAT 模式下 WSL2 会把 `localhost:端口` 自动转发进抽屉。
只有"局域网其他电脑要连"时才需要 portproxy。

---

## 4. GPU 的坑

### 4.1 显存是整卡的，不是独占的

**状态：实测确认**

`nvidia-smi` 显示 8188 MiB，但 Windows 桌面 + 浏览器已经吃掉一部分，
实际可用约 6–6.5 GB。

### 4.2 TDR 默认 2 秒会打断长 kernel

**状态：已知，未实测**

Windows 超时检测与恢复：GPU 2 秒无响应就重置驱动。长 kernel 会被杀。

```powershell
# 放宽到 60 秒，改完重启
reg add "HKLM\SYSTEM\CurrentControlSet\Control\GraphicsDrivers" /v TdrDelay /t REG_DWORD /d 60 /f
```

### 4.3 显存硬切分在 GeForce 上不存在，只能做软件闸

**状态：硬件事实 + 0.5.0 已实现软件闸**

MIG 只在 A100 / A30 / H100 / H200 / B200 上，GeForce 全系物理移除了这个能力。

0.5.0 起 `gpu.vram: N` 会在 `up` 时把 `vram\boxrun-vram.c` 编成 LD_PRELOAD 闸门，
拦 `cuMemAlloc(_v2 / _Managed / _Async / _Pitch)`，累计超过 N MiB 就返回
`CUDA_ERROR_OUT_OF_MEMORY`，让框架自己 OOM。

实测（RTX 5060 Laptop，256 MiB 一步）：

| 配置 | 结果 |
|---|---|
| 不加载闸门 | 8 次全过（2 GB） |
| `BOXRUN_VRAM_MB=512` | 第 3 次 `r=2` |
| `BOXRUN_VRAM_MB=1024` | 第 5 次 `r=2` |

**局限，别当安全边界**：

- 只对 `box.ps1 exec` 启动的进程生效，直接 `wsl -d lab` 进去跑的不受管；
- 不拦 `cuMemCreate`（VMM 预留，拦了会误伤正常框架）、CUDA graph、驱动内部池；
- 计数器是进程内的，多进程各算各的。

### 4.4 GPU 任务被 kill 时显存不一定释放

**状态：已知，未实测**

CUDA context 泄漏后 `nvidia-smi` 显示占用但没进程，只能重启驱动。

---

## 5. 隔离的坑

### 5.1 `interop` 默认开着 = 宿主权限

**状态：已知，实测已关闭（写进 wsl.conf）**

箱内能直接跑 `cmd.exe` / `powershell.exe`，能力完整。
不关它，cgroup、namespace、VPN 全都白设。

### 5.2 `automount` 默认开着 = 全盘可读

**状态：已知，实测已关闭（写进 wsl.conf）**

自动把 `C:` `D:` 挂成 `/mnt/c` `/mnt/d`。
不关它，箱内能读你所有文件。

---

## 6. 生命周期与残留

### 6.1 直接删抽屉文件夹会留孤儿注册项

**状态：已实现（`box.ps1 remove` 按正确顺序做）**

必须 `wsl --unregister`，它同时删 vhdx 和 `HKCU\...\Lxss` 下的项。
直接 `Remove-Item` 会在注册表留垃圾，`wsl -l` 还会显示它。

现在 `remove <name>` 的顺序是：撤锚点 → `--terminate` → `--unregister` → 删目录，
并且删除前要二次确认（GUI 里也是）。目录里的 `data/` 会一起没，确认框写明了。

### 6.2 `data/` 在 `state/` 下会被 unregister 吃掉

**状态：已知（设计上已避免），doctor 第 8 项检查**

### 6.3 计划任务用"不管用户是否登录都运行"会起错实例

**状态：已知，未实测**

以 SYSTEM 身份跑 `wsl.exe` 会创建 SYSTEM 的发行版实例，和用户会话的完全隔离。
服务看起来"活着"但连不上。必须用"用户登录时运行"。

---

## 7. 图形（WSLg）

### 7.1 关掉 interop 不影响 WSLg

**状态：实测确认（2026-11-11）**

WSLg 走的是独立的 Wayland + RDP 通道，和 `[interop] enabled=false` 无关。
实测：`/tmp/.X11-unix/X0` 在、`DISPLAY=:0`、`xeyes` / `xclock` 都建出了窗口。

### 7.2 不要为了图形去装 X server 或桌面环境

**状态：设计选择**

WSLg 已经给了 `:0`。再装 `xorg` / `xfce4` 只是多一层，还多一堆常驻进程。
真要"整桌面"才装 `xfce4` + `startxfce4`，日常用 `gui` 开单个应用就够。

### 7.3 GUI 程序要分离启动，而且只 `nohup` 不够

**状态：实测（踩过）**

`exec` 会一直等到程序退出（窗口关掉）。后台跑要用 `gui`，但第一版只做了
`nohup "$@" &`，结果 **pcmanfm 1 秒内还活着，`wsl.exe` 一退出就没了**；同样的写法
`xclock` 却能活。改成 `setsid "$@" </dev/null >>log 2>&1 &` 才稳定——新会话、无控制终端，
不依赖父进程。

日志在箱内 `/tmp/boxrun-gui.log`（每次启动前清空）。

### 7.4 窗口尺寸异常大是显示器缩放，不是 bug

**状态：实测**

`xeyes` 在 4K/缩放显示器上被拉成 `2548x1567`，是 WSLg 跟随 Windows 的 DPI 缩放，
不是程序算错；需要精确尺寸时在 Windows 侧调缩放，或在程序里自己设窗口大小。

### 7.5 Wayland 客户端不会出现在 X 窗口树里

**状态：实测**

WSLg 同时提供 Wayland（`wayland-0`）和 X（`:0`）。pcmanfm 默认走 Wayland，
`xwininfo -root -tree` 里**看不到**它——这不代表没有窗口。

要排查、或者要确保走 X11：

```powershell
.\box.ps1 gui lab env GDK_BACKEND=x11 pcmanfm /
```

这时窗口树里就有了：`"root": ("pcmanfm" "Pcmanfm") 640x480`。

---

## 待验证清单（按"能否杀死方案"排序）

| # | 验证项 | 失败后果 | 状态 |
|---|---|---|---|
| **1** | `HypervisorPresent = True` | 整个方案跑不起来 | ✅ 已通过（`lab` 已注册、vhdx 153 MB） |
| **2** | 箱内 `/sys/fs/cgroup/cgroup.controllers` 含 memory/cpu | 「限」这一域塌掉 | ✅ 实测通过 |
| **3** | 关 interop 后 WSLg `xeyes` 仍能弹窗 | 「用宿主桌面」塌掉 | ✅ 实测通过（`X0` 在、`xeyes` 常驻） |
| **4** | 箱内能读 `/usr/lib/wsl/lib/libcuda.so*` | GPU 可用性 | ✅ 实测通过（`/dev/dxg` 也在） |
| **5** | `mount -t drvfs` 挂 Windows 目录（关 automount 后） | 存储方案要换 rclone | ✅ 实测通过（双向可写） |

第 1 条已经用一次 `build` 换到了答案 —— 这就是"先验证再开发"的价值。
