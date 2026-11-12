# Edmund724/skills 一键安装与同步脚本
$ErrorActionPreference = "Stop"

$RepoUrl = "https://github.com/Edmund724/skills.git"
$DestDir = Join-Path $HOME ".agents\skills"
$PluginDir = Join-Path $HOME ".gemini\config\plugins\user-skills"
$GlobalAgentsMdDir = Join-Path $HOME ".gemini\config"

Write-Host "==> [1/4] 同步 skills 仓库..." -ForegroundColor Cyan
if (Test-Path "$DestDir\.git") {
    Write-Host "检测到本地已存在仓库，正在更新..."
    git -C "$DestDir" pull --ff-only
} else {
    if (Test-Path "$DestDir") {
        Write-Warning "目录 $DestDir 已存在但不是 Git 仓库，建议备份后清理再运行。"
    } else {
        New-Item -ItemType Directory -Force -Path (Split-Path $DestDir) | Out-Null
        git clone "$RepoUrl" "$DestDir"
    }
}

Write-Host "==> [2/4] 配置 Antigravity 插件元数据..." -ForegroundColor Cyan
if (!(Test-Path $PluginDir)) {
    New-Item -ItemType Directory -Force -Path $PluginDir | Out-Null
}
$PluginJson = Join-Path $PluginDir "plugin.json"
if (!(Test-Path $PluginJson)) {
    '{"name":"user-skills","displayName":"User Skills","version":"1.0.0"}' | Set-Content -Encoding utf8 -Path $PluginJson
}

Write-Host "==> [3/4] 建立 skills 目录联接 (Junction)..." -ForegroundColor Cyan
$PluginSkills = Join-Path $PluginDir "skills"
if (!(Test-Path $PluginSkills)) {
    cmd /c mklink /J "$PluginSkills" "$DestDir"
} else {
    Write-Host "联接已存在: $PluginSkills"
}

Write-Host "==> [4/4] 链接全局 AGENTS.md 规范 (Antigravity / kimi-code / dsh)..." -ForegroundColor Cyan
$SrcAgentsMd = Join-Path $DestDir "AGENTS.md"
$AgentDirs = @(
    (Join-Path $HOME ".gemini\config"),
    (Join-Path $HOME ".kimi-code"),
    (Join-Path $HOME ".dsh")
)

if (Test-Path $SrcAgentsMd) {
    foreach ($dir in $AgentDirs) {
        if (!(Test-Path $dir)) {
            New-Item -ItemType Directory -Force -Path $dir | Out-Null
        }
        $targetFile = Join-Path $dir "AGENTS.md"
        if (Test-Path $targetFile) {
            Remove-Item -Force $targetFile
        }
        try {
            New-Item -ItemType SymbolicLink -Path $targetFile -Target $SrcAgentsMd -ErrorAction Stop | Out-Null
            Write-Host "已建立符号链接: $targetFile -> $SrcAgentsMd"
        } catch {
            New-Item -ItemType HardLink -Path $targetFile -Target $SrcAgentsMd -ErrorAction Stop | Out-Null
            Write-Host "已建立硬链接: $targetFile <=> $SrcAgentsMd"
        }
    }
}

Write-Host "`n✔ 安装完成！Antigravity、kimi-code 与 dsh 已就绪并共享所有 Skills 与规范。" -ForegroundColor Green
