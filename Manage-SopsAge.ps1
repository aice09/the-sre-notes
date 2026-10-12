# Manage-SopsAge.ps1
# Windows PowerShell 5.1 compatible SOPS + age manager.
# Press Enter at the version prompt to use the latest stable version.
# Does not delete the age private key or unrelated files.

$ErrorActionPreference = "Stop"
$InstallDir = Join-Path $HOME ".local\bin"
$SopsPath = Join-Path $InstallDir "sops.exe"
$TempSopsPath = "$SopsPath.download"
$AgePackageId = "FiloSottile.age"
$AgeLinksDir = Join-Path $env:LOCALAPPDATA "Microsoft\WinGet\Links"
$AgeKeyPath = Join-Path $HOME ".config\sops\age\keys.txt"

function Refresh-Path {
    $machinePath = [Environment]::GetEnvironmentVariable("Path", "Machine")
    $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
    $env:Path = "$machinePath;$userPath"
}

function Get-PathEntries {
    param([string]$Scope)
    $value = [Environment]::GetEnvironmentVariable("Path", $Scope)
    if ([string]::IsNullOrWhiteSpace($value)) {
        return @()
    }
    return @($value -split ";" | Where-Object { $_ -and $_.Trim() })
}

function Add-PathEntry {
    param([string]$Directory)
    if ([string]::IsNullOrWhiteSpace($Directory)) {
        return
    }
    if (-not (Test-Path -LiteralPath $Directory -PathType Container)) {
        return
    }

    $userEntries = @(Get-PathEntries -Scope "User")
    $machineEntries = @(Get-PathEntries -Scope "Machine")
    $found = @($userEntries + $machineEntries | Where-Object {
        $_.Trim().TrimEnd("\") -ieq $Directory.Trim().TrimEnd("\")
    })

    if ($found.Count -eq 0) {
        $newPath = (@($userEntries) + $Directory) -join ";"
        [Environment]::SetEnvironmentVariable("Path", $newPath, "User")
        Write-Host "Added to User PATH: $Directory" -ForegroundColor Green
    }
    else {
        Write-Host "Already in PATH: $Directory"
    }
    Refresh-Path
}

function Remove-PathEntry {
    param([string]$Directory)
    if ([string]::IsNullOrWhiteSpace($Directory)) {
        return
    }

    foreach ($scope in @("User", "Machine")) {
        $entries = @(Get-PathEntries -Scope $scope)
        $kept = @($entries | Where-Object {
            $_.Trim().TrimEnd("\") -ine $Directory.Trim().TrimEnd("\")
        })

        if ($kept.Count -ne $entries.Count) {
            if ($scope -eq "Machine") {
                $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
                $principal = New-Object Security.Principal.WindowsPrincipal($identity)
                $isAdmin = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
                if (-not $isAdmin) {
                    Write-Host "Machine PATH removal requires an elevated PowerShell window: $Directory" -ForegroundColor Yellow
                    continue
                }
                [Environment]::SetEnvironmentVariable("Path", ($kept -join ";"), "Machine")
            }
            else {
                [Environment]::SetEnvironmentVariable("Path", ($kept -join ";"), "User")
            }
            Write-Host "Removed from $scope PATH: $Directory" -ForegroundColor Green
        }
    }
    Refresh-Path
}

function Clear-InstallMedia {
    if (Test-Path -LiteralPath $TempSopsPath -PathType Leaf) {
        Remove-Item -LiteralPath $TempSopsPath -Force
        Write-Host "Removed temporary SOPS download."
    }
}

function Read-VersionChoice {
    param([string]$ToolName, [string]$LatestVersion)
    Write-Host "$ToolName latest stable version: $LatestVersion" -ForegroundColor Cyan
    $inputVersion = Read-Host "Version to install (press Enter for latest)"
    if ([string]::IsNullOrWhiteSpace($inputVersion)) {
        return $LatestVersion
    }
    return $inputVersion.Trim().TrimStart("v")
}

function Install-OrUpdate-Sops {
    try {
        New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null

        $latest = Invoke-RestMethod -Uri "https://api.github.com/repos/getsops/sops/releases/latest"
        $latestVersion = $latest.tag_name.TrimStart("v")
        $version = Read-VersionChoice -ToolName "SOPS" -LatestVersion $latestVersion

        if ($version -eq $latestVersion) {
            $release = $latest
        }
        else {
            $release = Invoke-RestMethod -Uri "https://api.github.com/repos/getsops/sops/releases/tags/v$version"
        }

        $asset = $release.assets | Where-Object {
            $_.name -match '^sops-v\d+\.\d+\.\d+\.amd64\.exe$'
        } | Select-Object -First 1

        if ($null -eq $asset) {
            throw "No Windows AMD64 SOPS executable found for version $version."
        }

        Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $TempSopsPath

        if ((-not (Test-Path -LiteralPath $TempSopsPath -PathType Leaf)) -or ((Get-Item -LiteralPath $TempSopsPath).Length -eq 0)) {
            throw "SOPS download is missing or empty."
        }

        Move-Item -LiteralPath $TempSopsPath -Destination $SopsPath -Force
        Add-PathEntry -Directory $InstallDir
        Write-Host "Installed SOPS $($release.tag_name) at $SopsPath" -ForegroundColor Green
        Show-ToolStatus
    }
    catch {
        Write-Host "SOPS operation failed: $($_.Exception.Message)" -ForegroundColor Red
    }
    finally {
        Clear-InstallMedia
    }
}

function Install-OrUpdate-Age {
    try {
        if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
            throw "Winget is unavailable. Install Microsoft App Installer first."
        }

        $latest = Invoke-RestMethod -Uri "https://api.github.com/repos/FiloSottile/age/releases/latest"
        $latestVersion = $latest.tag_name.TrimStart("v")
        $version = Read-VersionChoice -ToolName "age" -LatestVersion $latestVersion

        $listing = winget list --id $AgePackageId --exact --accept-source-agreements 2>$null | Out-String
        $isInstalled = $listing -match [regex]::Escape($AgePackageId)

        if ($isInstalled) {
            $wingetArgs = @("upgrade", "--id", $AgePackageId, "--exact", "--accept-source-agreements", "--accept-package-agreements")
        }
        else {
            $wingetArgs = @("install", "--id", $AgePackageId, "--exact", "--accept-source-agreements", "--accept-package-agreements")
        }

        if ($version -ne $latestVersion) {
            $wingetArgs += @("--version", $version)
        }

        & winget @wingetArgs
        if ($LASTEXITCODE -ne 0) {
            throw "Winget failed to install/update age $version. Confirm the version is available in your Winget source."
        }

        Refresh-Path
        if (Test-Path -LiteralPath $AgeLinksDir -PathType Container) {
            Add-PathEntry -Directory $AgeLinksDir
        }

        foreach ($name in @("age", "age-keygen")) {
            $cmd = Get-Command $name -ErrorAction SilentlyContinue
            if ($null -ne $cmd -and $cmd.Source) {
                Add-PathEntry -Directory (Split-Path -Parent $cmd.Source)
            }
        }
        Show-ToolStatus
    }
    catch {
        Write-Host "age operation failed: $($_.Exception.Message)" -ForegroundColor Red
    }
    finally {
        Clear-InstallMedia
    }
}

function Remove-Sops {
    try {
        if (Test-Path -LiteralPath $SopsPath -PathType Leaf) {
            Remove-Item -LiteralPath $SopsPath -Force
            Write-Host "Removed SOPS: $SopsPath" -ForegroundColor Green
        }
        else {
            Write-Host "SOPS executable was not found at $SopsPath."
        }
    }
    catch {
        Write-Host "SOPS uninstall failed: $($_.Exception.Message)" -ForegroundColor Red
    }
    finally {
        Clear-InstallMedia
        $remaining = @()
        if (Test-Path -LiteralPath $InstallDir -PathType Container) {
            $remaining = @(Get-ChildItem -LiteralPath $InstallDir -Force)
        }
        if ($remaining.Count -eq 0) {
            Remove-PathEntry -Directory $InstallDir
        }
        else {
            Write-Host "Kept $InstallDir in PATH because it contains other files." -ForegroundColor Yellow
        }
    }
}

function Remove-Age {
    try {
        if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
            throw "Winget is unavailable; cannot uninstall age through Winget."
        }

        winget uninstall --id $AgePackageId --exact --accept-source-agreements
        if ($LASTEXITCODE -ne 0) {
            throw "Winget could not uninstall age. Check 'winget list --id $AgePackageId'."
        }
        Write-Host "age uninstalled. The age private key was preserved." -ForegroundColor Green
    }
    catch {
        Write-Host "age uninstall failed: $($_.Exception.Message)" -ForegroundColor Red
    }
    finally {
        Refresh-Path
        if (Test-Path -LiteralPath $AgeLinksDir -PathType Container) {
            $ageExists = Test-Path -LiteralPath (Join-Path $AgeLinksDir "age.exe")
            $keygenExists = Test-Path -LiteralPath (Join-Path $AgeLinksDir "age-keygen.exe")
            if ((-not $ageExists) -and (-not $keygenExists)) {
                Remove-PathEntry -Directory $AgeLinksDir
            }
        }
        Clear-InstallMedia
    }
}

function Show-ToolStatus {
    Refresh-Path

    Write-Host "`n--- SOPS ---" -ForegroundColor Cyan
    $sops = Get-Command sops -ErrorAction SilentlyContinue
    if ($sops) {
        Write-Host "Executable: $($sops.Source)"
        & $sops.Source --version
    }
    elseif (Test-Path -LiteralPath $SopsPath -PathType Leaf) {
        Write-Host "Executable: $SopsPath"
        & $SopsPath --version
    }
    else {
        Write-Host "Not found in PATH." -ForegroundColor Yellow
    }

    Write-Host "`n--- age ---" -ForegroundColor Cyan
    foreach ($name in @("age", "age-keygen")) {
        $cmd = Get-Command $name -ErrorAction SilentlyContinue
        if ($cmd) {
            Write-Host "$name path: $($cmd.Source)" -ForegroundColor Green
            if ($name -eq "age") {
                & $cmd.Source --version 2>$null
            }
        }
        else {
            Write-Host "$name not found in PATH." -ForegroundColor Yellow
        }
    }

    Write-Host "`n--- Installation paths and key ---" -ForegroundColor Cyan
    Write-Host "SOPS target: $SopsPath"
    Write-Host "age WinGet links: $AgeLinksDir"
    Write-Host "Age private key exists: $(Test-Path -LiteralPath $AgeKeyPath)"
    Write-Host "`nUser PATH:"
    Get-PathEntries -Scope "User" | ForEach-Object { Write-Host "  $_" }
    Write-Host "Machine PATH:"
    Get-PathEntries -Scope "Machine" | ForEach-Object { Write-Host "  $_" }
}

while ($true) {
    Clear-Host
    Write-Host "===== SOPS + age Manager =====" -ForegroundColor Cyan
    Write-Host "1. Install SOPS"
    Write-Host "2. Update SOPS"
    Write-Host "3. Uninstall SOPS"
    Write-Host "4. Install age"
    Write-Host "5. Update age"
    Write-Host "6. Uninstall age"
    Write-Host "7. Show status and installation paths"
    Write-Host "9. Exit"

    $choice = Read-Host "`nSelect an action"

    switch ($choice) {
        "1" { Install-OrUpdate-Sops }
        "2" { Install-OrUpdate-Sops }
        "3" { Remove-Sops }
        "4" { Install-OrUpdate-Age }
        "5" { Install-OrUpdate-Age }
        "6" { Remove-Age }
        "7" { Show-ToolStatus }
        "9" { return }
        default { Write-Host "Invalid choice." -ForegroundColor Yellow }
    }

    Read-Host "`nPress Enter to continue" | Out-Null
}
