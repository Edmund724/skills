# Agent Skills

个人 Agent Skills 与全局规则仓库。Antigravity 已原生发现 `~/.agents/skills` 中的自定义技能，本仓库的同步脚本仅负责同步全局规则 `AGENTS.md`、Antigravity 专属插件（`agy-fast-io`）及权限配置。

## 架构概览

| 文件 | 职责 |
| :--- | :--- |
| `targets.json` | 声明目标工具（`antigravity`、`dsh`）的探测路径与 `AGENTS.md` 规则链接配置 |
| `sync.ps1` | 本地幂等同步脚本，建立 `AGENTS.md` 链接、清理旧版重复技能目录，并同步 `agy-fast-io` 与 `config.json` 权限规则 |
| `install.ps1` | 远程一键引导脚本，负责克隆或更新仓库至 `~/.agents/skills` 并调用 `sync.ps1` |

## 新电脑一键安装 (Windows)

```powershell
irm https://raw.githubusercontent.com/Edmund724/skills/main/install.ps1 | iex
```

默认对 `antigravity` 始终执行；其他目标（如 `dsh`）仅在检测到配置目录时执行，不会自动创建。

## 日常同步

```powershell
# 仅执行本地幂等同步
& ~/.agents/skills/sync.ps1

# 拉取最新仓库（含 agy-fast-io）并同步
& ~/.agents/skills/sync.ps1 -Pull

# 只读预览即将发生的变更，不修改任何文件
& ~/.agents/skills/sync.ps1 -DryRun

# 仅同步指定目标
& ~/.agents/skills/sync.ps1 -Target antigravity
```
