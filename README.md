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
4. 将 `AGENTS.md` 规范以软/硬链接形式自动挂载至各个 Agent 全局目录：
   - `~/.gemini/config/AGENTS.md` (Antigravity)
   - `~/.kimi-code/AGENTS.md` (kimi-code)
   - `~/.dsh/AGENTS.md` (dsh)
5. 克隆 / 更新 [agy-fast-io](https://github.com/Edmund724/agy-fast-io) 到 `~/.agents/agy-fast-io`，并建立 `~/.gemini/config/plugins/fast-io` 到 `~/.agents/agy-fast-io/plugin` 的目录联接（若已存在非联接的旧目录，则先移出备份至 `~/.gemini/config/plugins-backup`）

## 日常更新

在任意终端重跑一键安装命令即可同时更新 `skills` 与 `agy-fast-io`，也可进入对应目录单独拉取：

```powershell
git -C ~/.agents/skills pull
git -C ~/.agents/agy-fast-io pull
```
