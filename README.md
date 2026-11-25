# Agent Skills

声明式多目标 Agent Skills 与全局规则仓库，通过按技能级目录联接（Junction）或受管副本，将同一份技能与 `AGENTS.md` 同步至 Antigravity、dsh、Codex、Claude 等工具。

## 架构概览

| 文件 | 职责 |
| :--- | :--- |
| `targets.json` | 声明各目标工具的探测路径、技能目录、同步模式（`junction` / `copy`）、排除规则与全局规则同步方式（`link` / `block`） |
| `sync.ps1` | 本地幂等同步引擎，执行逐技能挂载或复制、孤儿清理、规则同步，以及 Antigravity 专属插件（`agy-fast-io`）与权限规则合并 |
| `install.ps1` | 远程一键引导脚本，负责克隆或更新仓库至 `~/.agents/skills` 并调用 `sync.ps1` |

## 新电脑一键安装 (Windows)

```powershell
irm https://raw.githubusercontent.com/Edmund724/skills/main/install.ps1 | iex
```

默认仅对已检测到配置目录的工具执行同步（`antigravity` 为主环境始终执行），不会为未安装的工具自动创建配置目录。

## 日常同步

```powershell
# 仅执行本地幂等同步
& ~/.agents/skills/sync.ps1

# 拉取最新仓库（含 agy-fast-io）并同步
& ~/.agents/skills/sync.ps1 -Pull

# 只读预览即将发生的变更，不修改任何文件
& ~/.agents/skills/sync.ps1 -DryRun

# 仅同步指定目标
& ~/.agents/skills/sync.ps1 -Target antigravity,codex
```

## 扩展 `targets.json`

在 `targets` 数组中新增条目即可接入新工具，路径中的 `~` 会在运行时按当前 `$HOME` 展开：

```json
{
  "name": "example-tool",
  "detect": "~/.example",
  "skillsDir": "~/.example/skills",
  "mode": "junction",
  "exclude": ["draft-*"],
  "rules": {
    "src": "AGENTS.md",
    "dest": "~/.example/AGENTS.md",
    "mode": "block"
  }
}
```

- **技能发现**：仅挂载仓库根目录下直接包含 `SKILL.md` 的一级子目录，`exclude` 支持通配符（`-like`）过滤。
- **`mode = "junction"`**：逐技能建立目录联接，自动清理已删除或被排除的孤儿联接，保留目标目录中用户自建的真实目录与外部联接。
- **`mode = "copy"`**：复制技能目录并在 `skillsDir/.managed-skills.json` 中追踪托管清单，增量刷新并回收孤儿副本，不覆盖未列入清单的本地真实目录。
- **`rules.mode = "link"`**：优先建立符号链接，无权限时回退硬链接；若目标原为不同内容的普通文件，先备份为 `.bak-yyyyMMdd-HHmmss`。
- **`rules.mode = "block"`**：使用 `<!-- skills-sync:begin -->` / `<!-- skills-sync:end -->` 原地维护规则块，保留目标文件原有自定义内容。
