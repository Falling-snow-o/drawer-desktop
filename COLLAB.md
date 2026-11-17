# 协同模式（草案 + 实现说明）

## 目标

多个人在**同一个抽屉**上协作：各自改自己的副本，然后把改动**合并回一个抽屉**，像 git 一样。

## 现实约束

抽屉是完整的 WSL 发行版，包含：

- 系统层（rootfs、已装软件、/etc 配置）—— 二进制，无法逐字节三方合并
- 数据层（`data/`，箱内挂载为 `/work`）—— 普通文件，**可以**用 git 合并

所以协同分两层，优先级不同：

| 层 | 机制 | 冲突处理 |
|---|---|---|
| **数据层** `data/` | 标准 git（init/commit/pull/push/merge） | git 三方合并，文本冲突标出 |
| **环境层** 软件包 | 导出 `dpkg` 清单作为“环境快照”，合并时按清单补装 | 只做“缺什么装什么”，不删除对方装的包 |

> 系统镜像本身不做合并：所有人从同一个基础抽屉/镜像出发，差异靠“数据 + 包清单”收敛。

## 命令

```powershell
# 1) 把某个抽屉的 data/ 变成协同仓库，并推到共享远端
box.ps1 collab lab init <远端地址或本地裸仓库路径>

# 2) 看当前状态（未提交改动、领先/落后、远端）
box.ps1 collab lab status

# 3) 提交 + 拉取 + 推送（日常同步）
box.ps1 collab lab sync -m "改了实验脚本"

# 4) 保存当前环境清单（已装软件基线）
box.ps1 collab lab env-save

# 5) 看环境差异（相对基线）
box.ps1 collab lab env-diff

# 6) 把另一个抽屉的环境清单补装到当前抽屉
box.ps1 collab lab env-apply <清单文件>

# 7) 合并远端分支到当前抽屉的 data/
box.ps1 collab lab merge feature/xxx
```

## 合并流程（推荐）

1. 所有人 `collab init` 到同一个远端（或由一个人 init 后，其他人 clone 该远端到自己的 `data/`）
2. 日常：`collab sync -m "..."` 提交并推送
3. 要整合时：在目标抽屉 `collab merge <分支>`，解决文本冲突
4. 环境差异：`collab env-diff` 看差哪些包，`env-apply` 补装

## 不做什么

- 不做系统层三方合并（不可能可靠）
- 不做并发写同一抽屉（WSL 单实例，多人同时改会互相覆盖）
- 不替代代码托管：远端就是普通 git 仓库（GitHub/Gitee/本地裸仓库都行）
