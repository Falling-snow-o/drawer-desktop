# Agent 任务（实验）

让 Agent 在抽屉里改你的真实项目，但**改动先落在暂存目录**；确认后才写回宿主，失败直接丢弃。

## 工作方式

```
begin → 复制 host 目录到任务暂存 → 挂到 /work → git 记录基线
exec  → 在 /work 里执行命令 → 记录命令/输出/退出码/改动文件
end   → commit 写回 host；rollback 丢弃
```

- 每个任务一个目录：`%LOCALAPPDATA%\Drawer\tasks\<taskId>\`
- 暂存副本：`tasks\<taskId>\work`
- 记录仓库：`tasks\<taskId>\track.git`（不碰项目自己的 `.git`）
- 步骤日志：`tasks\<taskId>\steps.jsonl`

## 命令行

```powershell
# 开始任务（hostDir 可以是任意目录）
box.ps1 agent lab begin D:\work\project "修 bug"

# 在 /work 里执行（自动记录）
box.ps1 agent lab exec <taskId> "npm test"

# 结束：commit 写回宿主，rollback 丢弃
box.ps1 agent lab end <taskId> commit
box.ps1 agent lab end <taskId> rollback

# 查看
box.ps1 agent list
box.ps1 agent show <taskId>
```

`exec` 返回：

```json
{
  "seq": 3,
  "cmd": "npm test",
  "exit": 1,
  "changed": ["src/app.js"],
  "diff": "src/app.js | 4 ++--",
  "output": "..."
}
```

## MCP 接入

安装后 `drawer-mcp.exe` 在安装目录，Claude Code / Cursor / Codex 都能用。

Claude Code：

```powershell
claude mcp add drawer -- "C:\Users\<你>\AppData\Local\Drawer\drawer-mcp.exe"
```

或配置 JSON：

```json
{
  "mcpServers": {
    "drawer": {
      "command": "C:\\Users\\<你>\\AppData\\Local\\Drawer\\drawer-mcp.exe"
    }
  }
}
```

工具：

| 工具 | 作用 |
|---|---|
| `drawer_begin_task` | 开始任务，参数 `box`、`host_dir`、`name` |
| `drawer_exec` | 在 `/work` 执行命令 |
| `drawer_end_task` | `commit` 或 `rollback` |
| `drawer_task_status` | 查看任务和步骤 |
| `drawer_list_tasks` | 列出所有任务 |

## 安全边界

- Agent 只看到暂存副本，`commit` 之前宿主目录不变
- `.git` 不复制，项目历史不会被 agent 改动
- 任务期间 `/work` 指向暂存目录，结束后恢复原来的 `data/`
- **没有网络隔离**：Agent 仍可访问网络
- 建议一次只开一个任务；并发任务没有全局锁
- 大目录首次复制会慢

## 限制

- 没有界面（CLI + MCP 先用）
- 没有截图/鼠标键盘工具
- 二进制文件按文件复制，不做三方合并
- 宿主目录必须是普通目录，不支持网络盘
