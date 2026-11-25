& {
    $ErrorActionPreference = "Stop"

    $RepoUrl = "https://github.com/Edmund724/skills.git"
    $DestDir = Join-Path $HOME ".agents\skills"

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

    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        throw "未检测到 git，请先安装 Git 后重试。"
    }

    Write-Host "==> 同步 skills 仓库至 $DestDir..." -ForegroundColor Cyan
    if (Test-Path -LiteralPath (Join-Path $DestDir ".git")) {
        Invoke-Native { git -C "$DestDir" pull --ff-only } "skills git pull 失败"
    } else {
        if (Test-Path -LiteralPath $DestDir) {
            $backupDir = "$DestDir.bak-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
            Write-Warning "目录 $DestDir 已存在但不是 Git 仓库，正在备份至 $backupDir..."
            try {
                Move-Item -LiteralPath $DestDir -Destination $backupDir -ErrorAction Stop
            } catch {
                throw "无法备份旧目录 $DestDir（可能正被终端或编辑器占用），请关闭占用程序后重试: $($_.Exception.Message)"
            }
        }
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $DestDir) | Out-Null
        Invoke-Native { git clone "$RepoUrl" "$DestDir" } "skills git clone 失败"
    }

    $SyncScript = Join-Path $DestDir "sync.ps1"
    if (-not (Test-Path -LiteralPath $SyncScript -PathType Leaf)) {
        throw "未找到同步脚本: $SyncScript"
    }

    & $SyncScript
}
