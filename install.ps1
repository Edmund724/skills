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

Write-Host "==> [4/4] 同步全局 AGENTS.md 规则..." -ForegroundColor Cyan
$SrcAgentsMd = Join-Path $DestDir "AGENTS.md"
$DstAgentsMd = Join-Path $GlobalAgentsMdDir "AGENTS.md"
if (Test-Path $SrcAgentsMd) {
    if (!(Test-Path $GlobalAgentsMdDir)) {
        New-Item -ItemType Directory -Force -Path $GlobalAgentsMdDir | Out-Null
    }
    Copy-Item -Path $SrcAgentsMd -Destination $DstAgentsMd -Force
    Write-Host "已同步规则至: $DstAgentsMd"
}

Write-Host "`n✔ 安装完成！Antigravity 已就绪并加载所有 Skills 与全局规则。" -ForegroundColor Green
