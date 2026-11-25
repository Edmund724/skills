# Edmund724/skills 一键安装与同步脚本
& {
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

    function Ensure-JsonObjectProperty {
        param(
            [Parameter(Mandatory)] $Object,
            [Parameter(Mandatory)] [string]$Name,
            [Parameter(Mandatory)] $DefaultValue
        )
        $prop = $Object.PSObject.Properties[$Name]
        if (-not $prop -or $null -eq $prop.Value) {
            $Object | Add-Member -NotePropertyName $Name -NotePropertyValue $DefaultValue -Force
        }
        return $Object.PSObject.Properties[$Name].Value
    }

    function Merge-UniqueStringList {
        param(
            [Parameter(Mandatory)] $Container,
            [Parameter(Mandatory)] [string]$PropertyName,
            [Parameter(Mandatory)] [string[]]$RequiredItems
        )
        $prop = $Container.PSObject.Properties[$PropertyName]
        $current = if ($prop -and $null -ne $prop.Value) { @($prop.Value | ForEach-Object { [string]$_ }) } else { @() }
        $merged = [System.Collections.Generic.List[string]]::new()
        foreach ($item in $current) {
            if ($merged -cnotcontains $item) {
                $merged.Add($item)
            }
        }
        $addedCount = 0
        foreach ($item in $RequiredItems) {
            if ($merged -cnotcontains $item) {
                $merged.Add($item)
                $addedCount++
            }
        }
        if ($addedCount -gt 0 -or -not $prop -or $null -eq $prop.Value) {
            $Container | Add-Member -NotePropertyName $PropertyName -NotePropertyValue ([string[]]$merged.ToArray()) -Force
        }
        return $addedCount
    }

    function Sync-AntigravityPermissions {
        param(
            [Parameter(Mandatory)] [string]$ConfigPath,
            [Parameter(Mandatory)] [string[]]$AllowRules,
            [Parameter(Mandatory)] [string[]]$AskRules,
            [Parameter(Mandatory)] [string[]]$DenyRules
        )
        $configDir = Split-Path -Parent $ConfigPath
        if (-not (Test-Path -LiteralPath $configDir)) {
            New-Item -ItemType Directory -Force -Path $configDir | Out-Null
        }

        $exists = Test-Path -LiteralPath $ConfigPath
        if ($exists) {
            $raw = [System.IO.File]::ReadAllText($ConfigPath, [System.Text.UTF8Encoding]::new($false))
            if ([string]::IsNullOrWhiteSpace($raw)) {
                $config = [PSCustomObject]@{}
            } else {
                $config = $raw | ConvertFrom-Json -ErrorAction Stop
            }
        } else {
            $config = [PSCustomObject]@{}
        }

        $userSettings = Ensure-JsonObjectProperty -Object $config -Name "userSettings" -DefaultValue ([PSCustomObject]@{})
        $grants = Ensure-JsonObjectProperty -Object $userSettings -Name "globalPermissionGrants" -DefaultValue ([PSCustomObject]@{})

        $addedAllow = Merge-UniqueStringList -Container $grants -PropertyName "allow" -RequiredItems $AllowRules
        $addedAsk = Merge-UniqueStringList -Container $grants -PropertyName "ask" -RequiredItems $AskRules
        $addedDeny = Merge-UniqueStringList -Container $grants -PropertyName "deny" -RequiredItems $DenyRules
        $totalAdded = $addedAllow + $addedAsk + $addedDeny

        if ($exists -and $totalAdded -eq 0) {
            Write-Host "Antigravity allow/ask/deny 规则已是最新，无需修改 config.json。"
            return
        }

        if ($exists) {
            $backupPath = "$ConfigPath.bak-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
            Copy-Item -LiteralPath $ConfigPath -Destination $backupPath -Force
            Write-Host "已备份原配置至: $backupPath"
        }

        $jsonOut = $config | ConvertTo-Json -Depth 20
        [System.IO.File]::WriteAllText($ConfigPath, $jsonOut, [System.Text.UTF8Encoding]::new($false))
        Write-Host "已写入 Antigravity 权限规则（新增 allow: $addedAllow 条，ask: $addedAsk 条，deny: $addedDeny 条）。"
        Write-Warning "若 Antigravity 正在运行，请先重启应用以加载最新权限规则，并避免运行时写回覆盖。"
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

    Write-Host "==> [4/5] 链接全局 AGENTS.md 规范 (Antigravity / dsh)..." -ForegroundColor Cyan
    $SrcAgentsMd = Join-Path $DestDir "AGENTS.md"
    $AgentDirs = @(
        (Join-Path $HOME ".gemini\config"),
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

    Write-Host "==> [6/6] 同步 Antigravity 权限规则 (allow / ask / deny)..." -ForegroundColor Cyan
    $AntigravityConfigPath = Join-Path $HOME ".gemini\config\config.json"
    $AntigravityAllowRules = @(
        "command(rg)",
        "command(git status)",
        "command(git diff)",
        "command(git log)",
        "command(git show)",
        "command(git blame)",
        "command(git ls-files)",
        "command(git grep)",
        "command(git rev-parse)",
        "command(ls)",
        "command(dir)",
        "command(pwd)",
        "command(Get-ChildItem)",
        "command(Get-Location)",
        "command(Get-Command)",
        "command(Measure-Object)",
        "command(where.exe)",
        "command(tree)"
    )
    $AntigravityAskRules = @(
        "command(curl)",
        "command(Invoke-WebRequest)",
        "command(iwr)",
        "command(wget)",
        "command(Invoke-RestMethod)",
        "command(irm)",
        "command(del)",
        "command(Remove-Item)",
        "command(rm)",
        "command(ri)",
        "command(rmdir)",
        "command(rd)",
        "command(erase)",
        "command(Clear-Content)"
    )
    $AntigravityDenyRules = @(
        "command(rg --pre)",
        "command(git clean)",
        "command(format)",
        "command(git reset --hard)",
        "command(git checkout .)",
        "command(git stash)",
        "command(git commit --no-verify)",
        "command(git push --force)",
        "command(git push -f)",
        "read_file($(Join-Path $HOME '.dsh'))"
    )
    Sync-AntigravityPermissions -ConfigPath $AntigravityConfigPath -AllowRules $AntigravityAllowRules -AskRules $AntigravityAskRules -DenyRules $AntigravityDenyRules

    Write-Host "`n✔ 安装完成！Antigravity（含 fast-io 插件）与 dsh 已就绪并共享所有 Skills 与规范。" -ForegroundColor Green

}