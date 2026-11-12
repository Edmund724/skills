# Agent Skills

个人 Agent Skills 集合，通过目录联接直接接入 Antigravity 等 AI 编程助手。

## 新电脑一键安装 (Windows)

在 PowerShell 中直接运行以下一行命令即可全自动完成拉取、软链接建立、插件配置与全局规则同步：

```powershell
irm https://raw.githubusercontent.com/Edmund724/skills/main/install.ps1 | iex
```

该脚本将自动执行：
1. 克隆 / 更新仓库到 `~/.agents/skills`
2. 创建 Antigravity 插件目录 `~/.gemini/config/plugins/user-skills` 及配置
3. 建立 `~/.gemini/config/plugins/user-skills/skills` 到 `~/.agents/skills` 的目录联接（Junction）
4. 同步 `AGENTS.md` 行为准则至全局配置 `~/.gemini/config/AGENTS.md`

## 日常更新

在任意终端运行：

```powershell
cd ~/.agents/skills
git pull
```
