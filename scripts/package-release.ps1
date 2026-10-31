<#
.SYNOPSIS
    Builds, stages, and packages a release archive, standalone setup executable, and distribution manifests.

.DESCRIPTION
    Standardized release packaging tool for Project Kickstart repositories.
    Compiles release targets, stages binaries and documentation, compiles Inno Setup installer
    if iscc.exe is detected, creates portable .zip archives, computes SHA-256 checksums,
    and automatically generates WinGet and Scoop manifests.

.PARAMETER Version
    The semantic version string (e.g. "0.1.0"). If omitted, attempts to parse from project metadata.

.PARAMETER OutputDir
    Destination folder for release packages (default: "dist").

.PARAMETER SkipBuild
    If specified, skips the compilation/build step and only packages existing artifacts.
#>

[CmdletBinding()]
param(
    [string]$Version = "",
    [string]$OutputDir = "dist",
    [switch]$SkipBuild = $false
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
if (-not $ScriptDir) { $ScriptDir = (Get-Location).Path }
$RepoRoot = (Resolve-Path (Join-Path $ScriptDir "..")).Path
Set-Location $RepoRoot

$ProjectName = (Get-Item $RepoRoot).Name

# 1. Detect project version from single source of truth
if ([string]::IsNullOrWhiteSpace($Version)) {
    if (Test-Path (Join-Path $RepoRoot "package.json")) {
        $Pkg = Get-Content (Join-Path $RepoRoot "package.json") -Raw | ConvertFrom-Json
        $Version = $Pkg.version
    } elseif (Test-Path (Join-Path $RepoRoot "Cargo.toml")) {
        $CargoToml = Get-Content (Join-Path $RepoRoot "Cargo.toml") -Raw
        if ($CargoToml -match '\[(?:workspace\.)?package\][\s\S]*?version\s*=\s*"([^"]+)"') {
            $Version = $Matches[1].Trim()
        }
    } elseif (Test-Path (Join-Path $RepoRoot "pyproject.toml")) {
        $PyContent = Get-Content (Join-Path $RepoRoot "pyproject.toml") -Raw
        if ($PyContent -match 'version\s*=\s*"([^"]+)"') { $Version = $Matches[1].Trim() }
    }
}

if ([string]::IsNullOrWhiteSpace($Version)) {
    $Version = "0.1.0"
    Write-Warning "Could not detect version automatically. Defaulting to v$Version."
}

Write-Host "==================================================" -ForegroundColor Cyan
Write-Host "     $ProjectName Release Packaging Pipeline      " -ForegroundColor Cyan
Write-Host "==================================================" -ForegroundColor Cyan
Write-Host "Project: $ProjectName | Version: v$Version"

# 2. Build release target if not skipped
if (-not $SkipBuild) {
    Write-Host "`n[1/5] Compiling release targets..." -ForegroundColor Yellow
    if (Test-Path (Join-Path $RepoRoot "Cargo.toml")) {
        $env:PATH = "$env:USERPROFILE\.cargo\bin;$env:PATH"
        cargo build --workspace --release
    } elseif (Test-Path (Join-Path $RepoRoot "package.json")) {
        npm run build
    }
} else {
    Write-Host "`n[1/5] Skipping build step (-SkipBuild specified)..." -ForegroundColor Yellow
}

# 3. Prepare staging directories
$DistDir = Join-Path $RepoRoot $OutputDir
if (-not (Test-Path $DistDir)) { New-Item -ItemType Directory -Path $DistDir -Force | Out-Null }

$PackageName = "$ProjectName-v$Version-windows-x64"
$StageDir = Join-Path $DistDir "staging\$PackageName"
$ZipPath = Join-Path $DistDir "$PackageName.zip"

if (Test-Path $StageDir) { Remove-Item -Path $StageDir -Recurse -Force }
if (Test-Path $ZipPath) { Remove-Item -Path $ZipPath -Force }

New-Item -ItemType Directory -Path $StageDir -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $StageDir "scripts") -Force | Out-Null

# 4. Copy binaries & assets (Single-Binary Principle)
Write-Host "`n[2/5] Staging release assets and scripts..." -ForegroundColor Cyan
$CandidateBinaries = @(
    (Join-Path $RepoRoot "target\release\$ProjectName.exe"),
    (Join-Path $RepoRoot "$ProjectName.exe")
)
$FoundBinary = $CandidateBinaries | Where-Object { Test-Path $_ } | Select-Object -First 1
if ($FoundBinary) {
    Copy-Item $FoundBinary $StageDir -Force
    # Stage single-file installer executable
    $SetupExe = Join-Path $DistDir "$ProjectName-Setup.exe"
    Copy-Item $FoundBinary $SetupExe -Force
    Write-Host "  - Standalone setup executable staged: $SetupExe" -ForegroundColor Green
}

# Copy scripts & documentation
Copy-Item (Join-Path $RepoRoot "README.md") $StageDir -ErrorAction SilentlyContinue
Copy-Item (Join-Path $RepoRoot "LICENSE") $StageDir -ErrorAction SilentlyContinue
Copy-Item (Join-Path $RepoRoot "CHANGELOG.md") $StageDir -ErrorAction SilentlyContinue
Copy-Item (Join-Path $RepoRoot "docs\user-guide.md") $StageDir -ErrorAction SilentlyContinue
Copy-Item (Join-Path $RepoRoot "setup.cmd") $StageDir -ErrorAction SilentlyContinue
Copy-Item (Join-Path $ScriptDir "setup-wizard.ps1") (Join-Path $StageDir "scripts") -ErrorAction SilentlyContinue
Copy-Item (Join-Path $ScriptDir "install.ps1") (Join-Path $StageDir "scripts") -ErrorAction SilentlyContinue
Copy-Item (Join-Path $ScriptDir "uninstall.ps1") (Join-Path $StageDir "scripts") -ErrorAction SilentlyContinue

# 5. Inno Setup Compiler check (Optional Native Installer)
Write-Host "`n[3/5] Checking for Inno Setup compiler (iscc.exe)..." -ForegroundColor Cyan
$CandidateIscc = @(
    (Get-Command iscc.exe -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source -ErrorAction SilentlyContinue),
    "${env:ProgramFiles(x86)}\Inno Setup 6\iscc.exe",
    "$env:ProgramFiles\Inno Setup 6\iscc.exe"
)
$IsccExe = $CandidateIscc | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1
$InstallerIss = Join-Path $ScriptDir "installer.iss"

if ($IsccExe -and (Test-Path $InstallerIss)) {
    Write-Host "  Compiling native Windows installer with Inno Setup..." -ForegroundColor Green
    & $IsccExe "/DMyAppVersion=$Version" $InstallerIss
} else {
    Write-Host "  Inno Setup not detected; standalone portable bundle and script wizard ready." -ForegroundColor Gray
}

# 6. Create portable ZIP archive
Write-Host "`n[4/5] Creating portable release archive: $ZipPath" -ForegroundColor Cyan
Compress-Archive -Path "$StageDir\*" -DestinationPath $ZipPath -Force

# 7. Compute SHA-256 hash & generate manifests
Write-Host "`n[5/5] Computing checksums and generating package manifests..." -ForegroundColor Cyan
$Hash = (Get-FileHash -Path $ZipPath -Algorithm SHA256).Hash.ToUpperInvariant()
$HashFile = "$ZipPath.sha256"
Set-Content -Path $HashFile -Value "$Hash  $([System.IO.Path]::GetFileName($ZipPath))" -Encoding utf8

$GenManifestsScript = Join-Path $ScriptDir "generate-manifests.ps1"
if (Test-Path $GenManifestsScript) {
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File $GenManifestsScript -Version $Version -ZipPath $ZipPath
}

Write-Host "`n==================================================" -ForegroundColor Green
Write-Host "       Release Packaging Completed Successfully!  " -ForegroundColor Green
Write-Host "==================================================" -ForegroundColor Green
Write-Host "Archive:  $ZipPath"
Write-Host "SHA-256:  $Hash"
