# Edmund724/skills 一键安装与同步脚本
$ErrorActionPreference = "Stop"

$RepoUrl = "https://github.com/Edmund724/skills.git"
$DestDir = Join-Path $HOME ".agents\skills"
$PluginDir = Join-Path $HOME ".gemini\config\plugins\user-skills"
$FastIoRepoUrl = "https://github.com/Edmund724/agy-fast-io.git"
$FastIoDir = Join-Path $HOME ".agents\agy-fast-io"
$FastIoPluginLink = Join-Path $HOME ".gemini\config\plugins\fast-io"
$PluginBackupDir = Join-Path $HOME ".gemini\config\plugins-backup"

function Invoke-Native {
    param(
        [Parameter(Mandatory)] [scriptblock]$Command,
        [Parameter(Mandatory)] [string]$ErrorMessage
    )
    $global:LASTEXITCODE = 0
    & $Command
    if ($LASTEXITCODE -ne 0) {
        throw "$ErrorMessage (退出码: $LASTEXITCODE)"
    }
}

function Sync-GitRepo {
    param(
        [Parameter(Mandatory)] [string]$RepoUrl,
        [Parameter(Mandatory)] [string]$DestDir,
        [Parameter(Mandatory)] [string]$Label
    )
    if (Test-Path -LiteralPath (Join-Path $DestDir ".git")) {
        Write-Host "检测到本地已存在 $Label 仓库，正在更新..."
        Invoke-Native { git -C "$DestDir" pull --ff-only } "$Label git pull 失败"
        return
    }
    if (Test-Path -LiteralPath $DestDir) {
        $BackupDir = "$DestDir.bak-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
        Write-Warning "目录 $DestDir 已存在但不是 Git 仓库，正在备份至 $BackupDir..."
        try {
            Move-Item -LiteralPath $DestDir -Destination $BackupDir -ErrorAction Stop
        } catch {
            throw "无法备份旧目录 $DestDir（可能正被终端或编辑器占用），请关闭占用程序后重试: $($_.Exception.Message)"
        }
    }
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $DestDir) | Out-Null
    Invoke-Native { git clone "$RepoUrl" "$DestDir" } "$Label git clone 失败"
}

function Test-LinkToTarget {
    param(
        [Parameter(Mandatory)] $Item,
        [Parameter(Mandatory)] [string]$ExpectedTarget
    )
    if (-not ($Item.Attributes -band [System.IO.FileAttributes]::ReparsePoint)) {
        return $false
    }
    $normExpected = $ExpectedTarget.TrimEnd('\')
    return [bool](@($Item.Target) | Where-Object { $_ -and ($_.TrimEnd('\') -eq $normExpected) })
}

function Set-DirectoryJunction {
    param(
        [Parameter(Mandatory)] [string]$LinkPath,
        [Parameter(Mandatory)] [string]$TargetPath,
        [string]$BackupRoot
    )
    if (-not (Test-Path -LiteralPath $TargetPath)) {
        throw "联接目标目录不存在: $TargetPath"
    }
    $existing = Get-Item -LiteralPath $LinkPath -Force -ErrorAction SilentlyContinue
    if ($existing) {
        if (Test-LinkToTarget -Item $existing -ExpectedTarget $TargetPath) {
            Write-Host "联接已存在: $LinkPath -> $TargetPath"
            return
        }
        if ($existing.Attributes -band [System.IO.FileAttributes]::ReparsePoint) {
            Invoke-Native { cmd /c rmdir "$LinkPath" } "移除旧联接失败: $LinkPath"
        } elseif ($BackupRoot) {
            New-Item -ItemType Directory -Force -Path $BackupRoot | Out-Null
            $leaf = Split-Path -Leaf $LinkPath
            $backupPath = Join-Path $BackupRoot "$leaf.bak-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
            Write-Warning "路径 $LinkPath 已存在且不是目录联接，正在移出备份至 $backupPath..."
            try {
                Move-Item -LiteralPath $LinkPath -Destination $backupPath -ErrorAction Stop
            } catch {
                throw "无法备份旧目录 $LinkPath（可能正被占用），请关闭占用程序后重试: $($_.Exception.Message)"
            }
        } else {
            throw "路径 $LinkPath 已存在且不是目录联接，请备份清理后重试。"
        }
    }
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $LinkPath) | Out-Null
    Invoke-Native { cmd /c mklink /J "$LinkPath" "$TargetPath" } "创建目录联接失败: $LinkPath -> $TargetPath"
}

function Set-FileLink {
    param(
        [Parameter(Mandatory)] [string]$LinkPath,
        [Parameter(Mandatory)] [string]$TargetPath
    )
    if (-not (Test-Path -LiteralPath $TargetPath)) {
        throw "未找到源文件: $TargetPath"
    }
    $parentDir = Split-Path -Parent $LinkPath
    if (-not (Test-Path -LiteralPath $parentDir)) {
        New-Item -ItemType Directory -Force -Path $parentDir | Out-Null
    }
    if (Get-Item -LiteralPath $LinkPath -Force -ErrorAction SilentlyContinue) {
        Remove-Item -LiteralPath $LinkPath -Force
    }
    try {
        New-Item -ItemType SymbolicLink -Path $LinkPath -Target $TargetPath -ErrorAction Stop | Out-Null
        Write-Host "已建立符号链接: $LinkPath -> $TargetPath"
    } catch {
        New-Item -ItemType HardLink -Path $LinkPath -Target $TargetPath -ErrorAction Stop | Out-Null
        Write-Host "已建立硬链接: $LinkPath <=> $TargetPath"
    }
}

if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    throw "未检测到 git，请先安装 Git 后重试。"
}

Write-Host "==> [1/5] 同步 skills 仓库..." -ForegroundColor Cyan
Sync-GitRepo -RepoUrl $RepoUrl -DestDir $DestDir -Label "skills"

Write-Host "==> [2/5] 配置 Antigravity 插件元数据..." -ForegroundColor Cyan
if (-not (Test-Path -LiteralPath $PluginDir)) {
    New-Item -ItemType Directory -Force -Path $PluginDir | Out-Null
}
$PluginJson = Join-Path $PluginDir "plugin.json"
if (-not (Test-Path -LiteralPath $PluginJson)) {
    $jsonContent = '{"name":"user-skills","displayName":"User Skills","version":"1.0.0"}'
    [System.IO.File]::WriteAllText($PluginJson, $jsonContent, [System.Text.UTF8Encoding]::new($false))
}

Write-Host "==> [3/5] 建立 skills 目录联接 (Junction)..." -ForegroundColor Cyan
$LegacyGlobalSkills = Join-Path $HOME ".gemini\config\skills"
$legacyItem = Get-Item -LiteralPath $LegacyGlobalSkills -Force -ErrorAction SilentlyContinue
if ($legacyItem) {
    if (Test-LinkToTarget -Item $legacyItem -ExpectedTarget $DestDir) {
        Invoke-Native { cmd /c rmdir "$LegacyGlobalSkills" } "移除重复旧联接失败: $LegacyGlobalSkills"
        Write-Host "已移除重复的旧全局联接: $LegacyGlobalSkills"
    } else {
        Write-Warning "检测到 $LegacyGlobalSkills 已存在，若包含同名技能可能导致 Antigravity 重复加载，请按需清理。"
    }
}

$PluginSkills = Join-Path $PluginDir "skills"
Set-DirectoryJunction -LinkPath $PluginSkills -TargetPath $DestDir

Write-Host "==> [4/5] 链接全局 AGENTS.md 规范 (Antigravity / kimi-code / dsh)..." -ForegroundColor Cyan
$SrcAgentsMd = Join-Path $DestDir "AGENTS.md"
$AgentDirs = @(
    (Join-Path $HOME ".gemini\config"),
    (Join-Path $HOME ".kimi-code"),
    (Join-Path $HOME ".dsh")
)

foreach ($dir in $AgentDirs) {
    Set-FileLink -LinkPath (Join-Path $dir "AGENTS.md") -TargetPath $SrcAgentsMd
}

Write-Host "==> [5/5] 同步并安装 Antigravity 插件 (fast-io)..." -ForegroundColor Cyan
Sync-GitRepo -RepoUrl $FastIoRepoUrl -DestDir $FastIoDir -Label "agy-fast-io"

# Antigravity 扫描 plugins/<name> 时不识别顶层 Junction，因此插件根目录须为真实目录，rules 子目录使用 Junction
$FastIoPluginSrc = Join-Path $FastIoDir "plugin"
$FastIoRulesTarget = Join-Path $FastIoPluginSrc "rules"
$FastIoRulesLink = Join-Path $FastIoPluginLink "rules"

$existingFastIo = Get-Item -LiteralPath $FastIoPluginLink -Force -ErrorAction SilentlyContinue
if ($existingFastIo) {
    if ($existingFastIo.Attributes -band [System.IO.FileAttributes]::ReparsePoint) {
        Invoke-Native { cmd /c rmdir "$FastIoPluginLink" } "移除旧插件联接失败: $FastIoPluginLink"
    } else {
        $existingRules = Get-Item -LiteralPath $FastIoRulesLink -Force -ErrorAction SilentlyContinue
        if (-not ($existingRules -and (Test-LinkToTarget -Item $existingRules -ExpectedTarget $FastIoRulesTarget))) {
            New-Item -ItemType Directory -Force -Path $PluginBackupDir | Out-Null
            $backupPath = Join-Path $PluginBackupDir "fast-io.bak-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
            Write-Warning "路径 $FastIoPluginLink 已存在且非脚本接管目录，正在移出备份至 $backupPath..."
            try {
                Move-Item -LiteralPath $FastIoPluginLink -Destination $backupPath -ErrorAction Stop
            } catch {
                throw "无法备份旧插件目录 $FastIoPluginLink（可能正被占用），请关闭占用程序后重试: $($_.Exception.Message)"
            }
        }
    }
}

if (-not (Test-Path -LiteralPath $FastIoPluginLink)) {
    New-Item -ItemType Directory -Force -Path $FastIoPluginLink | Out-Null
}
Set-FileLink -LinkPath (Join-Path $FastIoPluginLink "plugin.json") -TargetPath (Join-Path $FastIoPluginSrc "plugin.json")
$FastIoReadmeSrc = Join-Path $FastIoPluginSrc "README.md"
if (Test-Path -LiteralPath $FastIoReadmeSrc) {
    Set-FileLink -LinkPath (Join-Path $FastIoPluginLink "README.md") -TargetPath $FastIoReadmeSrc
}
Set-DirectoryJunction -LinkPath $FastIoRulesLink -TargetPath $FastIoRulesTarget -BackupRoot $PluginBackupDir

Write-Host "`n✔ 安装完成！Antigravity（含 fast-io 插件）、kimi-code 与 dsh 已就绪并共享所有 Skills 与规范。" -ForegroundColor Green
