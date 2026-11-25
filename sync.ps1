[CmdletBinding()]
param(
    [switch]$Pull,
    [switch]$DryRun,
    [string[]]$Target
)

$ErrorActionPreference = "Stop"

$Utf8NoBom = [System.Text.UTF8Encoding]::new($false)
$RepoRoot = [System.IO.Path]::GetFullPath($PSScriptRoot)
$ConfigFile = Join-Path $RepoRoot "targets.json"
$ManifestFileName = ".managed-skills.json"
$BlockBegin = "<!-- skills-sync:begin -->"
$BlockEnd = "<!-- skills-sync:end -->"
$FastIoRepoUrl = "https://github.com/Edmund724/agy-fast-io.git"

function Write-Action {
    param(
        [Parameter(Mandatory)] [string]$Message
    )
    if ($DryRun) {
        Write-Host "[DRY-RUN] $Message" -ForegroundColor DarkYellow
    } else {
        Write-Host $Message
    }
}

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

function Expand-UserPath {
    param(
        [Parameter(Mandatory)] [string]$Path
    )
    if ($Path -eq "~") {
        $expanded = $HOME
    } elseif ($Path -match '^~[\\/]') {
        $relative = $Path.Substring(2).Replace('/', '\')
        $expanded = Join-Path $HOME $relative
    } else {
        $expanded = $Path.Replace('/', '\')
    }
    return [System.IO.Path]::GetFullPath($expanded)
}

function Normalize-ComparePath {
    param(
        [Parameter(Mandatory)] [string]$Path
    )
    $clean = $Path.Trim()
    if ($clean.StartsWith("\??\")) {
        $clean = $clean.Substring(4)
    }
    if ($clean.Length -gt 3) {
        $clean = $clean.TrimEnd('\', '/')
    }
    return $clean
}

function Get-ReparseTargets {
    param(
        [Parameter(Mandatory)] $Item
    )
    if (-not ($Item.Attributes -band [System.IO.FileAttributes]::ReparsePoint)) {
        return @()
    }
    return @($Item.Target | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object { Normalize-ComparePath $_ })
}

function Test-LinkToTarget {
    param(
        [Parameter(Mandatory)] $Item,
        [Parameter(Mandatory)] [string]$ExpectedTarget
    )
    $targets = Get-ReparseTargets -Item $Item
    if ($targets.Count -eq 0) {
        return $false
    }
    $normExpected = Normalize-ComparePath $ExpectedTarget
    return [bool]($targets | Where-Object { $_ -ieq $normExpected })
}

function Test-PathUnderRoot {
    param(
        [Parameter(Mandatory)] [string]$CandidatePath,
        [Parameter(Mandatory)] [string]$RootPath
    )
    $normCandidate = Normalize-ComparePath $CandidatePath
    $normRoot = Normalize-ComparePath $RootPath
    if ($normCandidate -ieq $normRoot) {
        return $true
    }
    return $normCandidate.StartsWith("$normRoot\", [System.StringComparison]::OrdinalIgnoreCase)
}

function Test-LinkUnderRoot {
    param(
        [Parameter(Mandatory)] $Item,
        [Parameter(Mandatory)] [string]$RootPath
    )
    $targets = Get-ReparseTargets -Item $Item
    foreach ($t in $targets) {
        if (Test-PathUnderRoot -CandidatePath $t -RootPath $RootPath) {
            return $true
        }
    }
    return $false
}

function Remove-JunctionSafe {
    param(
        [Parameter(Mandatory)] [string]$LinkPath,
        [Parameter(Mandatory)] [string]$Reason
    )
    if ($DryRun) {
        Write-Action "将移除目录联接 ($Reason): $LinkPath"
        return
    }
    Invoke-Native { cmd /c rmdir "$LinkPath" } "移除目录联接失败: $LinkPath"
    Write-Action "已移除目录联接 ($Reason): $LinkPath"
}

function New-JunctionSafe {
    param(
        [Parameter(Mandatory)] [string]$LinkPath,
        [Parameter(Mandatory)] [string]$TargetPath
    )
    if (-not (Test-Path -LiteralPath $TargetPath)) {
        throw "联接目标目录不存在: $TargetPath"
    }
    if ($DryRun) {
        Write-Action "将创建目录联接: $LinkPath -> $TargetPath"
        return
    }
    $parentDir = Split-Path -Parent $LinkPath
    if (-not (Test-Path -LiteralPath $parentDir)) {
        New-Item -ItemType Directory -Force -Path $parentDir | Out-Null
    }
    Invoke-Native { cmd /c mklink /J "$LinkPath" "$TargetPath" | Out-Null } "创建目录联接失败: $LinkPath -> $TargetPath"
    Write-Action "已创建目录联接: $LinkPath -> $TargetPath"
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
            return
        }
        if ($existing.Attributes -band [System.IO.FileAttributes]::ReparsePoint) {
            Remove-JunctionSafe -LinkPath $LinkPath -Reason "更新联接目标"
        } elseif ($BackupRoot) {
            $leaf = Split-Path -Leaf $LinkPath
            $backupPath = Join-Path $BackupRoot "$leaf.bak-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
            if ($DryRun) {
                Write-Action "将备份旧目录 $LinkPath -> $backupPath"
            } else {
                New-Item -ItemType Directory -Force -Path $BackupRoot | Out-Null
                Write-Warning "路径 $LinkPath 已存在且不是目录联接，正在移出备份至 $backupPath..."
                try {
                    Move-Item -LiteralPath $LinkPath -Destination $backupPath -ErrorAction Stop
                } catch {
                    throw "无法备份旧目录 $LinkPath（可能正被占用），请关闭占用程序后重试: $($_.Exception.Message)"
                }
            }
        } else {
            throw "路径 $LinkPath 已存在且不是目录联接，请备份清理后重试。"
        }
    }
    New-JunctionSafe -LinkPath $LinkPath -TargetPath $TargetPath
}

function Test-SameFileContent {
    param(
        [Parameter(Mandatory)] [string]$PathA,
        [Parameter(Mandatory)] [string]$PathB
    )
    $bytesA = [System.IO.File]::ReadAllBytes($PathA)
    $bytesB = [System.IO.File]::ReadAllBytes($PathB)
    if ($bytesA.Length -ne $bytesB.Length) {
        return $false
    }
    for ($i = 0; $i -lt $bytesA.Length; $i++) {
        if ($bytesA[$i] -ne $bytesB[$i]) {
            return $false
        }
    }
    return $true
}

function Set-FileLink {
    param(
        [Parameter(Mandatory)] [string]$LinkPath,
        [Parameter(Mandatory)] [string]$TargetPath
    )
    if (-not (Test-Path -LiteralPath $TargetPath)) {
        throw "未找到源文件: $TargetPath"
    }
    $existing = Get-Item -LiteralPath $LinkPath -Force -ErrorAction SilentlyContinue
    if ($existing) {
        if ($existing.LinkType -eq "SymbolicLink" -and (Test-LinkToTarget -Item $existing -ExpectedTarget $TargetPath)) {
            return
        }
        if ($existing.LinkType -eq "HardLink" -and (Test-SameFileContent -PathA $LinkPath -PathB $TargetPath)) {
            return
        }
        if ([string]::IsNullOrEmpty($existing.LinkType)) {
            if (-not (Test-SameFileContent -PathA $LinkPath -PathB $TargetPath)) {
                $backupPath = "$LinkPath.bak-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
                if ($DryRun) {
                    Write-Action "将备份现有规则文件: $LinkPath -> $backupPath"
                } else {
                    Copy-Item -LiteralPath $LinkPath -Destination $backupPath -Force
                    Write-Host "已备份原文件至: $backupPath"
                }
            }
        }
        if ($DryRun) {
            Write-Action "将替换文件链接: $LinkPath -> $TargetPath"
            return
        }
        Remove-Item -LiteralPath $LinkPath -Force
    } elseif ($DryRun) {
        Write-Action "将建立文件链接: $LinkPath -> $TargetPath"
        return
    }

    $parentDir = Split-Path -Parent $LinkPath
    if (-not (Test-Path -LiteralPath $parentDir)) {
        New-Item -ItemType Directory -Force -Path $parentDir | Out-Null
    }
    try {
        New-Item -ItemType SymbolicLink -Path $LinkPath -Target $TargetPath -ErrorAction Stop | Out-Null
        Write-Action "已建立符号链接: $LinkPath -> $TargetPath"
    } catch {
        New-Item -ItemType HardLink -Path $LinkPath -Target $TargetPath -ErrorAction Stop | Out-Null
        Write-Action "已建立硬链接: $LinkPath <=> $TargetPath"
    }
}

function Sync-RuleBlock {
    param(
        [Parameter(Mandatory)] [string]$SrcPath,
        [Parameter(Mandatory)] [string]$DestPath
    )
    if (-not (Test-Path -LiteralPath $SrcPath)) {
        throw "未找到源规则文件: $SrcPath"
    }
    $srcRaw = [System.IO.File]::ReadAllText($SrcPath, $Utf8NoBom)
    $nl = if ($srcRaw.Contains("`r`n")) { "`r`n" } else { "`n" }
    $srcBody = $srcRaw.TrimEnd("`r", "`n")
    $block = "$BlockBegin$nl$srcBody$nl$BlockEnd"

    $existing = Get-Item -LiteralPath $DestPath -Force -ErrorAction SilentlyContinue
    if ($existing -and -not [string]::IsNullOrEmpty($existing.LinkType)) {
        $isLinkedToSrc = ($existing.LinkType -eq "SymbolicLink" -and (Test-LinkToTarget -Item $existing -ExpectedTarget $SrcPath)) -or
            ($existing.LinkType -eq "HardLink" -and (Test-SameFileContent -PathA $DestPath -PathB $SrcPath))
        if ($isLinkedToSrc) {
            $newContent = "$block$nl"
            if ($DryRun) {
                Write-Action "将解除旧规则链接并写入 block 托管文件: $DestPath"
                return
            }
            Remove-Item -LiteralPath $DestPath -Force
            [System.IO.File]::WriteAllText($DestPath, $newContent, $Utf8NoBom)
            Write-Action "已解除旧规则链接并转为 block 托管文件: $DestPath"
            return
        }
        $existingContent = [System.IO.File]::ReadAllText($DestPath, $Utf8NoBom)
        if ($DryRun) {
            Write-Action "将解除外部链接并转为独立 block 托管文件: $DestPath"
            return
        }
        Remove-Item -LiteralPath $DestPath -Force
        $destContent = $existingContent
    } elseif ($existing) {
        $destContent = [System.IO.File]::ReadAllText($DestPath, $Utf8NoBom)
    } else {
        $newContent = "$block$nl"
        if ($DryRun) {
            Write-Action "将创建规则文件 (block): $DestPath"
            return
        }
        $parentDir = Split-Path -Parent $DestPath
        if (-not (Test-Path -LiteralPath $parentDir)) {
            New-Item -ItemType Directory -Force -Path $parentDir | Out-Null
        }
        [System.IO.File]::WriteAllText($DestPath, $newContent, $Utf8NoBom)
        Write-Action "已创建规则文件 (block): $DestPath"
        return
    }

    $destNl = if ($destContent.Contains("`r`n")) { "`r`n" } else { $nl }
    $normalizedBlock = $block.Replace("`r`n", "`n").Replace("`n", $destNl)
    $pattern = "(?s)$([regex]::Escape($BlockBegin)).*?$([regex]::Escape($BlockEnd))"

    if ([regex]::IsMatch($destContent, $pattern)) {
        $newContent = [regex]::Replace($destContent, $pattern, [System.Text.RegularExpressions.MatchEvaluator]{
            param($m)
            return $normalizedBlock
        }, 1)
    } elseif ([string]::IsNullOrWhiteSpace($destContent)) {
        $newContent = "$normalizedBlock$destNl"
    } else {
        $trimmed = $destContent.TrimEnd("`r", "`n")
        $newContent = "$trimmed$destNl$destNl$normalizedBlock$destNl"
    }

    if ($newContent -ceq $destContent) {
        return
    }
    if ($DryRun) {
        Write-Action "将更新规则块 (block): $DestPath"
        return
    }
    [System.IO.File]::WriteAllText($DestPath, $newContent, $Utf8NoBom)
    Write-Action "已更新规则块 (block): $DestPath"
}

function Get-SourceSkills {
    param(
        [Parameter(Mandatory)] [string]$Root,
        [string[]]$ExcludePatterns
    )
    $dirs = Get-ChildItem -LiteralPath $Root -Directory | Sort-Object Name
    $result = [System.Collections.Generic.List[System.IO.DirectoryInfo]]::new()
    foreach ($dir in $dirs) {
        if (-not (Test-Path -LiteralPath (Join-Path $dir.FullName "SKILL.md") -PathType Leaf)) {
            continue
        }
        $excluded = $false
        foreach ($pattern in @($ExcludePatterns)) {
            if (-not [string]::IsNullOrWhiteSpace($pattern) -and ($dir.Name -like $pattern)) {
                $excluded = $true
                break
            }
        }
        if (-not $excluded) {
            $result.Add($dir)
        }
    }
    return $result
}

function Initialize-SkillsDir {
    param(
        [Parameter(Mandatory)] [string]$SkillsDir
    )
    $existing = Get-Item -LiteralPath $SkillsDir -Force -ErrorAction SilentlyContinue
    if ($existing) {
        if ($existing.Attributes -band [System.IO.FileAttributes]::ReparsePoint) {
            if (Test-LinkToTarget -Item $existing -ExpectedTarget $RepoRoot) {
                Remove-JunctionSafe -LinkPath $SkillsDir -Reason "迁移整目录联接"
                if ($DryRun) {
                    Write-Action "将创建技能目录: $SkillsDir"
                    return @{ Ready = $true; CanInspectChildren = $false }
                }
                New-Item -ItemType Directory -Force -Path $SkillsDir | Out-Null
                Write-Action "已创建技能目录: $SkillsDir"
                return @{ Ready = $true; CanInspectChildren = $true }
            }
            Write-Error "技能目录 $SkillsDir 是指向未知目标的联接 ($(@($existing.Target) -join ', '))，已中止该目标，请手工检查。" -ErrorAction Continue
            return @{ Ready = $false; CanInspectChildren = $false }
        }
        return @{ Ready = $true; CanInspectChildren = $true }
    }

    if ($DryRun) {
        Write-Action "将创建技能目录: $SkillsDir"
        return @{ Ready = $true; CanInspectChildren = $false }
    }
    New-Item -ItemType Directory -Force -Path $SkillsDir | Out-Null
    return @{ Ready = $true; CanInspectChildren = $true }
}

function Sync-SkillsJunctionMode {
    param(
        [Parameter(Mandatory)] [string]$SkillsDir,
        [Parameter(Mandatory)] [System.Collections.Generic.List[System.IO.DirectoryInfo]]$ActiveSkills,
        [Parameter(Mandatory)] [bool]$CanInspectChildren
    )
    $activeNames = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($skill in $ActiveSkills) {
        [void]$activeNames.Add($skill.Name)
    }

    foreach ($skill in $ActiveSkills) {
        $linkPath = Join-Path $SkillsDir $skill.Name
        if (-not $CanInspectChildren) {
            New-JunctionSafe -LinkPath $linkPath -TargetPath $skill.FullName
            continue
        }
        $existing = Get-Item -LiteralPath $linkPath -Force -ErrorAction SilentlyContinue
        if ($existing) {
            if (Test-LinkToTarget -Item $existing -ExpectedTarget $skill.FullName) {
                continue
            }
            if (Test-LinkUnderRoot -Item $existing -RootPath $RepoRoot) {
                Remove-JunctionSafe -LinkPath $linkPath -Reason "修正技能联接"
                New-JunctionSafe -LinkPath $linkPath -TargetPath $skill.FullName
            } else {
                Write-Warning "跳过同名本地目录或外部联接: $linkPath"
            }
        } else {
            New-JunctionSafe -LinkPath $linkPath -TargetPath $skill.FullName
        }
    }

    if (-not $CanInspectChildren) {
        return
    }

    foreach ($item in (Get-ChildItem -LiteralPath $SkillsDir -Force)) {
        if (-not ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint)) {
            continue
        }
        if (-not (Test-LinkUnderRoot -Item $item -RootPath $RepoRoot)) {
            continue
        }
        if (-not $activeNames.Contains($item.Name)) {
            Remove-JunctionSafe -LinkPath $item.FullName -Reason "清理孤儿联接"
        }
    }
}

function Read-ManagedManifest {
    param(
        [Parameter(Mandatory)] [string]$ManifestPath
    )
    $set = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    if (-not (Test-Path -LiteralPath $ManifestPath -PathType Leaf)) {
        return $set
    }
    $raw = [System.IO.File]::ReadAllText($ManifestPath, $Utf8NoBom)
    if ([string]::IsNullOrWhiteSpace($raw)) {
        return $set
    }
    $parsed = $raw | ConvertFrom-Json -ErrorAction Stop
    foreach ($entry in @($parsed)) {
        if (-not [string]::IsNullOrWhiteSpace([string]$entry)) {
            [void]$set.Add([string]$entry)
        }
    }
    return $set
}

function Sync-SkillsCopyMode {
    param(
        [Parameter(Mandatory)] [string]$SkillsDir,
        [Parameter(Mandatory)] [System.Collections.Generic.List[System.IO.DirectoryInfo]]$ActiveSkills,
        [Parameter(Mandatory)] [bool]$CanInspectChildren
    )
    $manifestPath = Join-Path $SkillsDir $ManifestFileName
    $managedSet = if ($CanInspectChildren) {
        Read-ManagedManifest -ManifestPath $manifestPath
    } else {
        [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    }

    $activeNames = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($skill in $ActiveSkills) {
        [void]$activeNames.Add($skill.Name)
    }

    $nextManaged = [System.Collections.Generic.List[string]]::new()

    foreach ($skill in $ActiveSkills) {
        $destSkillDir = Join-Path $SkillsDir $skill.Name
        $existing = if ($CanInspectChildren) {
            Get-Item -LiteralPath $destSkillDir -Force -ErrorAction SilentlyContinue
        } else {
            $null
        }

        if (-not $existing) {
            if ($DryRun) {
                Write-Action "将复制技能目录: $($skill.FullName) -> $destSkillDir"
            } else {
                Copy-Item -LiteralPath $skill.FullName -Destination $destSkillDir -Recurse -Force
                Write-Action "已复制技能目录: $destSkillDir"
            }
            $nextManaged.Add($skill.Name)
            continue
        }

        if (($existing.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -and (Test-LinkUnderRoot -Item $existing -RootPath $RepoRoot)) {
            Remove-JunctionSafe -LinkPath $destSkillDir -Reason "切换为 copy 模式"
            if ($DryRun) {
                Write-Action "将复制技能目录: $($skill.FullName) -> $destSkillDir"
            } else {
                Copy-Item -LiteralPath $skill.FullName -Destination $destSkillDir -Recurse -Force
                Write-Action "已复制技能目录: $destSkillDir"
            }
            $nextManaged.Add($skill.Name)
            continue
        }

        if ($managedSet.Contains($skill.Name) -and -not ($existing.Attributes -band [System.IO.FileAttributes]::ReparsePoint)) {
            if ($DryRun) {
                Write-Action "将刷新托管技能副本: $destSkillDir"
            } else {
                Remove-Item -LiteralPath $destSkillDir -Recurse -Force
                Copy-Item -LiteralPath $skill.FullName -Destination $destSkillDir -Recurse -Force
                Write-Action "已刷新托管技能副本: $destSkillDir"
            }
            $nextManaged.Add($skill.Name)
            continue
        }

        Write-Warning "跳过未托管的本地目录或外部联接: $destSkillDir"
    }

    if ($CanInspectChildren) {
        foreach ($oldName in $managedSet) {
            if ($activeNames.Contains($oldName)) {
                continue
            }
            $orphanPath = Join-Path $SkillsDir $oldName
            $orphanItem = Get-Item -LiteralPath $orphanPath -Force -ErrorAction SilentlyContinue
            if (-not $orphanItem) {
                continue
            }
            if ($orphanItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) {
                Remove-JunctionSafe -LinkPath $orphanPath -Reason "清理孤儿托管项"
            } elseif ($DryRun) {
                Write-Action "将删除孤儿托管副本: $orphanPath"
            } else {
                Remove-Item -LiteralPath $orphanPath -Recurse -Force
                Write-Action "已删除孤儿托管副本: $orphanPath"
            }
        }
    }

    $sortedNext = @($nextManaged | Sort-Object -Unique)
    $manifestJson = ConvertTo-Json -InputObject $sortedNext -Depth 5
    if ($DryRun) {
        Write-Action "将更新托管清单: $manifestPath"
        return
    }
    $currentRaw = if (Test-Path -LiteralPath $manifestPath -PathType Leaf) {
        [System.IO.File]::ReadAllText($manifestPath, $Utf8NoBom)
    } else {
        $null
    }
    if ($currentRaw -cne $manifestJson) {
        [System.IO.File]::WriteAllText($manifestPath, $manifestJson, $Utf8NoBom)
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
    $exists = Test-Path -LiteralPath $ConfigPath
    if ($exists) {
        $raw = [System.IO.File]::ReadAllText($ConfigPath, $Utf8NoBom)
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

    if ($DryRun) {
        Write-Action "将写入 Antigravity 权限规则至 $ConfigPath（新增 allow: $addedAllow 条，ask: $addedAsk 条，deny: $addedDeny 条）"
        return
    }

    $configDir = Split-Path -Parent $ConfigPath
    if (-not (Test-Path -LiteralPath $configDir)) {
        New-Item -ItemType Directory -Force -Path $configDir | Out-Null
    }

    if ($exists) {
        $backupPath = "$ConfigPath.bak-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
        Copy-Item -LiteralPath $ConfigPath -Destination $backupPath -Force
        Write-Host "已备份原配置至: $backupPath"
    }

    $jsonOut = $config | ConvertTo-Json -Depth 20
    [System.IO.File]::WriteAllText($ConfigPath, $jsonOut, $Utf8NoBom)
    Write-Host "已写入 Antigravity 权限规则（新增 allow: $addedAllow 条，ask: $addedAsk 条，deny: $addedDeny 条）。"
    Write-Warning "若 Antigravity 正在运行，请先重启应用以加载最新权限规则，并避免运行时写回覆盖。"
}

function Sync-AntigravityExtras {
    $geminiConfigDir = Expand-UserPath "~/.gemini/config"
    $legacyGlobalSkills = Join-Path $geminiConfigDir "skills"
    $legacyItem = Get-Item -LiteralPath $legacyGlobalSkills -Force -ErrorAction SilentlyContinue
    if ($legacyItem) {
        if (Test-LinkToTarget -Item $legacyItem -ExpectedTarget $RepoRoot) {
            Remove-JunctionSafe -LinkPath $legacyGlobalSkills -Reason "移除重复旧全局联接"
        } else {
            Write-Warning "检测到 $legacyGlobalSkills 已存在，若包含同名技能可能导致 Antigravity 重复加载，请按需清理。"
        }
    }

    $fastIoDir = Expand-UserPath "~/.agents/agy-fast-io"
    $fastIoPluginLink = Join-Path $geminiConfigDir "plugins\fast-io"
    $pluginBackupDir = Join-Path $geminiConfigDir "plugins-backup"

    if (-not (Test-Path -LiteralPath $fastIoDir)) {
        if ($DryRun) {
            Write-Action "将克隆 agy-fast-io 到 $fastIoDir"
        } else {
            if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
                throw "未检测到 git，无法克隆 agy-fast-io。"
            }
            New-Item -ItemType Directory -Force -Path (Split-Path -Parent $fastIoDir) | Out-Null
            Invoke-Native { git clone "$FastIoRepoUrl" "$fastIoDir" } "agy-fast-io git clone 失败"
        }
    }

    $fastIoPluginSrc = Join-Path $fastIoDir "plugin"
    $fastIoRulesTarget = Join-Path $fastIoPluginSrc "rules"
    $fastIoRulesLink = Join-Path $fastIoPluginLink "rules"

    if (Test-Path -LiteralPath $fastIoPluginSrc) {
        $existingFastIo = Get-Item -LiteralPath $fastIoPluginLink -Force -ErrorAction SilentlyContinue
        if ($existingFastIo) {
            if ($existingFastIo.Attributes -band [System.IO.FileAttributes]::ReparsePoint) {
                Remove-JunctionSafe -LinkPath $fastIoPluginLink -Reason "重建 fast-io 真实插件目录"
            } else {
                $existingRules = Get-Item -LiteralPath $fastIoRulesLink -Force -ErrorAction SilentlyContinue
                if (-not ($existingRules -and (Test-LinkToTarget -Item $existingRules -ExpectedTarget $fastIoRulesTarget))) {
                    $backupPath = Join-Path $pluginBackupDir "fast-io.bak-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
                    if ($DryRun) {
                        Write-Action "将备份旧插件目录: $fastIoPluginLink -> $backupPath"
                    } else {
                        New-Item -ItemType Directory -Force -Path $pluginBackupDir | Out-Null
                        Write-Warning "路径 $fastIoPluginLink 已存在且非脚本接管目录，正在移出备份至 $backupPath..."
                        try {
                            Move-Item -LiteralPath $fastIoPluginLink -Destination $backupPath -ErrorAction Stop
                        } catch {
                            throw "无法备份旧插件目录 $fastIoPluginLink（可能正被占用），请关闭占用程序后重试: $($_.Exception.Message)"
                        }
                    }
                }
            }
        }

        if (-not (Test-Path -LiteralPath $fastIoPluginLink)) {
            if ($DryRun) {
                Write-Action "将创建 fast-io 插件目录: $fastIoPluginLink"
            } else {
                New-Item -ItemType Directory -Force -Path $fastIoPluginLink | Out-Null
            }
        }

        $fastIoPluginJsonSrc = Join-Path $fastIoPluginSrc "plugin.json"
        if (Test-Path -LiteralPath $fastIoPluginJsonSrc) {
            Set-FileLink -LinkPath (Join-Path $fastIoPluginLink "plugin.json") -TargetPath $fastIoPluginJsonSrc
        }
        $fastIoReadmeSrc = Join-Path $fastIoPluginSrc "README.md"
        if (Test-Path -LiteralPath $fastIoReadmeSrc) {
            Set-FileLink -LinkPath (Join-Path $fastIoPluginLink "README.md") -TargetPath $fastIoReadmeSrc
        }
        if (Test-Path -LiteralPath $fastIoRulesTarget) {
            Set-DirectoryJunction -LinkPath $fastIoRulesLink -TargetPath $fastIoRulesTarget -BackupRoot $pluginBackupDir
        }
    }

    $antigravityConfigPath = Join-Path $geminiConfigDir "config.json"
    $allowRules = @(
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
    $askRules = @(
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
    $denyRules = @(
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
    Sync-AntigravityPermissions -ConfigPath $antigravityConfigPath -AllowRules $allowRules -AskRules $askRules -DenyRules $denyRules
}

if (-not (Test-Path -LiteralPath $ConfigFile -PathType Leaf)) {
    throw "未找到配置文件: $ConfigFile"
}

$manifest = [System.IO.File]::ReadAllText($ConfigFile, $Utf8NoBom) | ConvertFrom-Json -ErrorAction Stop
$allTargets = @($manifest.targets)

if ($Target -and $Target.Count -gt 0) {
    $requestedTargets = @(
        $Target |
            ForEach-Object { $_ -split ',' } |
            ForEach-Object { $_.Trim() } |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    )
    $knownNames = @($allTargets | ForEach-Object { $_.name })
    foreach ($req in $requestedTargets) {
        if ($knownNames -notcontains $req) {
            throw "未知目标名称: $req（可用目标: $($knownNames -join ', ')）"
        }
    }
    $selectedTargets = @($allTargets | Where-Object { $requestedTargets -contains $_.name })
} else {
    $selectedTargets = $allTargets
}

$antigravitySelected = [bool]($selectedTargets | Where-Object { $_.name -ieq "antigravity" })

if ($Pull) {
    if ($DryRun) {
        Write-Action "将执行 git pull --ff-only: $RepoRoot"
        $fastIoDir = Expand-UserPath "~/.agents/agy-fast-io"
        if ($antigravitySelected -and (Test-Path -LiteralPath (Join-Path $fastIoDir ".git"))) {
            Write-Action "将执行 git pull --ff-only: $fastIoDir"
        }
    } else {
        if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
            throw "未检测到 git，请先安装 Git 后重试。"
        }
        Write-Host "==> 拉取最新 skills 仓库..." -ForegroundColor Cyan
        Invoke-Native { git -C "$RepoRoot" pull --ff-only } "skills git pull 失败"
        $fastIoDir = Expand-UserPath "~/.agents/agy-fast-io"
        if ($antigravitySelected -and (Test-Path -LiteralPath (Join-Path $fastIoDir ".git"))) {
            Write-Host "==> 拉取最新 agy-fast-io 仓库..." -ForegroundColor Cyan
            Invoke-Native { git -C "$fastIoDir" pull --ff-only } "agy-fast-io git pull 失败"
        }
    }
}

foreach ($t in $selectedTargets) {
    $detectDir = Expand-UserPath $t.detect
    if (-not (Test-Path -LiteralPath $detectDir) -and ($t.name -ine "antigravity")) {
        Write-Host "跳过目标 $($t.name)：未检测到 $detectDir" -ForegroundColor DarkGray
        continue
    }

    Write-Host "==> 同步目标: $($t.name) ($($t.mode))" -ForegroundColor Cyan

    if ($t.PSObject.Properties["pluginJson"] -and $null -ne $t.pluginJson) {
        $pluginJsonPath = Expand-UserPath $t.pluginJson.path
        if (-not (Test-Path -LiteralPath $pluginJsonPath)) {
            if ($DryRun) {
                Write-Action "将创建插件元数据: $pluginJsonPath"
            } else {
                $pluginDir = Split-Path -Parent $pluginJsonPath
                if (-not (Test-Path -LiteralPath $pluginDir)) {
                    New-Item -ItemType Directory -Force -Path $pluginDir | Out-Null
                }
                $pluginJsonText = $t.pluginJson.content | ConvertTo-Json -Depth 10
                [System.IO.File]::WriteAllText($pluginJsonPath, $pluginJsonText, $Utf8NoBom)
                Write-Action "已创建插件元数据: $pluginJsonPath"
            }
        }
    }

    $skillsDir = Expand-UserPath $t.skillsDir
    $dirState = Initialize-SkillsDir -SkillsDir $skillsDir
    if (-not $dirState.Ready) {
        continue
    }

    $excludeList = if ($t.PSObject.Properties["exclude"] -and $null -ne $t.exclude) { @($t.exclude) } else { @() }
    $activeSkills = Get-SourceSkills -Root $RepoRoot -ExcludePatterns $excludeList

    switch ($t.mode) {
        "junction" {
            Sync-SkillsJunctionMode -SkillsDir $skillsDir -ActiveSkills $activeSkills -CanInspectChildren $dirState.CanInspectChildren
        }
        "copy" {
            Sync-SkillsCopyMode -SkillsDir $skillsDir -ActiveSkills $activeSkills -CanInspectChildren $dirState.CanInspectChildren
        }
        default {
            throw "目标 $($t.name) 配置了不支持的同步模式: $($t.mode)"
        }
    }

    if ($t.PSObject.Properties["rules"] -and $null -ne $t.rules) {
        $ruleSrcRaw = [string]$t.rules.src
        $ruleSrc = if ($ruleSrcRaw -match '^~' -or [System.IO.Path]::IsPathRooted($ruleSrcRaw)) {
            Expand-UserPath $ruleSrcRaw
        } else {
            [System.IO.Path]::GetFullPath((Join-Path $RepoRoot $ruleSrcRaw))
        }
        $ruleDest = Expand-UserPath $t.rules.dest
        switch ($t.rules.mode) {
            "link" {
                Set-FileLink -LinkPath $ruleDest -TargetPath $ruleSrc
            }
            "block" {
                Sync-RuleBlock -SrcPath $ruleSrc -DestPath $ruleDest
            }
            default {
                throw "目标 $($t.name) 配置了不支持的规则模式: $($t.rules.mode)"
            }
        }
    }
}

$geminiConfigDir = Expand-UserPath "~/.gemini/config"
if ($antigravitySelected -and ((Test-Path -LiteralPath $geminiConfigDir) -or $DryRun)) {
    Write-Host "==> 同步 Antigravity 专属扩展与权限规则..." -ForegroundColor Cyan
    Sync-AntigravityExtras
}

Write-Host "同步完成。" -ForegroundColor Green
