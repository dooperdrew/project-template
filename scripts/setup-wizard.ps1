<#
.SYNOPSIS
    Guided Windows Setup Wizard for {{PROJECT_NAME}}.

.DESCRIPTION
    Provides a zero-elevation graphical (Windows Forms) and interactive console wizard to install
    the application into %LOCALAPPDATA%\Programs\<ProjectName>, configure Start Menu and Desktop
    shortcuts, add to user PATH (optional), set up logon autostart (optional), register Windows
    "Installed apps" uninstaller entry, and launch upon completion.

.PARAMETER TargetDir
    Installation directory. Defaults to "$env:LOCALAPPDATA\Programs\{{PROJECT_NAME}}".

.PARAMETER NoDesktopShortcut
    Disables creating the desktop shortcut.

.PARAMETER NoStartMenuShortcut
    Disables creating Start Menu shortcuts.

.PARAMETER AddPath
    Adds the TargetDir to User environment PATH.

.PARAMETER EnableAutostart
    Configures application to start automatically on Windows sign-in (HKCU).

.PARAMETER NoLaunch
    Prevents launching the application upon installation completion.

.PARAMETER Silent
    Runs installation unattended with no GUI or prompts using default or specified parameters.

.PARAMETER NoGui
    Forces interactive console wizard instead of Windows Forms GUI.
#>

[CmdletBinding()]
param(
    [string]$TargetDir = "",
    [switch]$NoDesktopShortcut,
    [switch]$NoStartMenuShortcut,
    [switch]$AddPath,
    [switch]$EnableAutostart,
    [switch]$NoLaunch,
    [switch]$Silent,
    [switch]$NoGui
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
if (-not $ScriptDir) { $ScriptDir = (Get-Location).Path }
$RepoRoot = (Resolve-Path (Join-Path $ScriptDir "..")).Path
$ProjectName = (Get-Item $RepoRoot).Name

if ([string]::IsNullOrWhiteSpace($TargetDir)) {
    $TargetDir = Join-Path $env:LOCALAPPDATA "Programs\$ProjectName"
}

# Auto-detect version
$Version = "0.1.0"
if (Test-Path (Join-Path $RepoRoot "package.json")) {
    $Version = (Get-Content (Join-Path $RepoRoot "package.json") -Raw | ConvertFrom-Json).version
} elseif (Test-Path (Join-Path $RepoRoot "Cargo.toml")) {
    $CargoContent = Get-Content (Join-Path $RepoRoot "Cargo.toml") -Raw
    if ($CargoContent -match 'version\s*=\s*"([^"]+)"') { $Version = $Matches[1].Trim() }
}

function Invoke-Installation {
    param(
        [string]$DestDir,
        [bool]$CreateDesktop,
        [bool]$CreateStartMenu,
        [bool]$SetPath,
        [bool]$SetAutostart,
        [bool]$LaunchApp
    )

    Write-Host "Installing $ProjectName v$Version to $DestDir..." -ForegroundColor Cyan

    # Stop any running instances
    Get-Process -Name $ProjectName -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue

    New-Item -ItemType Directory -Path $DestDir -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $DestDir "locales") -Force -ErrorAction SilentlyContinue | Out-Null

    # Copy binaries & release assets
    $CandidateBinaries = @(
        (Join-Path $ScriptDir "$ProjectName.exe"),
        (Join-Path $RepoRoot "target\release\$ProjectName.exe"),
        (Join-Path $RepoRoot "$ProjectName.exe")
    )

    $AppExe = $CandidateBinaries | Where-Object { Test-Path $_ } | Select-Object -First 1
    if ($AppExe) {
        Copy-Item -Path $AppExe -Destination (Join-Path $DestDir "$ProjectName.exe") -Force
    }

    # Copy locales, docs, and uninstaller
    Copy-Item (Join-Path $RepoRoot "README.md") $DestDir -ErrorAction SilentlyContinue
    Copy-Item (Join-Path $RepoRoot "LICENSE") $DestDir -ErrorAction SilentlyContinue
    Copy-Item (Join-Path $ScriptDir "uninstall.ps1") $DestDir -ErrorAction SilentlyContinue

    $WshShell = New-Object -ComObject WScript.Shell
    $TargetExe = Join-Path $DestDir "$ProjectName.exe"

    # Start Menu Shortcut
    if ($CreateStartMenu) {
        $StartMenuPrograms = [Environment]::GetFolderPath('Programs')
        $AppStartMenuDir = Join-Path $StartMenuPrograms $ProjectName
        New-Item -ItemType Directory -Path $AppStartMenuDir -Force | Out-Null

        $AppShortcut = $WshShell.CreateShortcut((Join-Path $AppStartMenuDir "$ProjectName.lnk"))
        $AppShortcut.TargetPath = $TargetExe
        $AppShortcut.WorkingDirectory = $DestDir
        $AppShortcut.Save()

        $UninstShortcut = $WshShell.CreateShortcut((Join-Path $AppStartMenuDir "Uninstall $ProjectName.lnk"))
        $UninstShortcut.TargetPath = "powershell.exe"
        $UninstShortcut.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$DestDir\uninstall.ps1`""
        $UninstShortcut.WorkingDirectory = $DestDir
        $UninstShortcut.Save()
    }

    # Desktop Shortcut
    if ($CreateDesktop) {
        $DesktopPath = [Environment]::GetFolderPath('Desktop')
        $DesktopShortcut = $WshShell.CreateShortcut((Join-Path $DesktopPath "$ProjectName.lnk"))
        $DesktopShortcut.TargetPath = $TargetExe
        $DesktopShortcut.WorkingDirectory = $DestDir
        $DesktopShortcut.Save()
    }

    # User PATH registration
    if ($SetPath) {
        $UserPath = [Environment]::GetEnvironmentVariable("Path", "User")
        if ($null -eq $UserPath) { $UserPath = "" }
        if ($UserPath -notlike "*$DestDir*") {
            $NewPath = if ([string]::IsNullOrWhiteSpace($UserPath)) { $DestDir } else { "$UserPath;$DestDir" }
            [Environment]::SetEnvironmentVariable("Path", $NewPath, "User")
        }
    }

    # Autostart registration (HKCU)
    $RunKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
    if ($SetAutostart) {
        Set-ItemProperty -Path $RunKey -Name $ProjectName -Value "`"$TargetExe`"" -Force
    }

    # Windows Add/Remove Programs (Installed apps) registration
    $UninstallKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\$ProjectName"
    New-Item -Path $UninstallKey -Force | Out-Null
    Set-ItemProperty -Path $UninstallKey -Name "DisplayName" -Value "$ProjectName" -Force
    Set-ItemProperty -Path $UninstallKey -Name "DisplayVersion" -Value "$Version" -Force
    Set-ItemProperty -Path $UninstallKey -Name "Publisher" -Value "Contributors" -Force
    Set-ItemProperty -Path $UninstallKey -Name "InstallLocation" -Value "$DestDir" -Force
    Set-ItemProperty -Path $UninstallKey -Name "UninstallString" -Value "powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$DestDir\uninstall.ps1`"" -Force
    Set-ItemProperty -Path $UninstallKey -Name "DisplayIcon" -Value "$TargetExe" -Force

    Write-Host "Installation completed successfully!" -ForegroundColor Green

    # Launch application
    if ($LaunchApp -and (Test-Path $TargetExe)) {
        Start-Process -FilePath $TargetExe -WorkingDirectory $DestDir
    }
}

# Silent / Non-GUI Execution
if ($Silent -or $NoGui) {
    Invoke-Installation `
        -DestDir $TargetDir `
        -CreateDesktop (-not $NoDesktopShortcut) `
        -CreateStartMenu (-not $NoStartMenuShortcut) `
        -SetPath $AddPath `
        -SetAutostart $EnableAutostart `
        -LaunchApp (-not $NoLaunch)
    exit 0
}

# Windows Forms GUI Setup Wizard
try {
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing

    $Form = New-Object System.Windows.Forms.Form
    $Form.Text = "$ProjectName Setup Wizard (v$Version)"
    $Form.Size = New-Object System.Drawing.Size(520, 420)
    $Form.StartPosition = "CenterScreen"
    $Form.FormBorderStyle = "FixedDialog"
    $Form.MaximizeBox = $false

    $Header = New-Object System.Windows.Forms.Label
    $Header.Text = "Welcome to $ProjectName Setup"
    $Header.Font = New-Object System.Drawing.Font("Segoe UI", 14, [System.Drawing.FontStyle]::Bold)
    $Header.Location = New-Object System.Drawing.Point(24, 20)
    $Header.Size = New-Object System.Drawing.Size(460, 32)
    $Form.Controls.Add($Header)

    $SubHeader = New-Object System.Windows.Forms.Label
    $SubHeader.Text = "This wizard will install $ProjectName on your computer (no admin rights needed)."
    $SubHeader.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    $SubHeader.Location = New-Object System.Drawing.Point(26, 56)
    $SubHeader.Size = New-Object System.Drawing.Size(460, 24)
    $Form.Controls.Add($SubHeader)

    $DirLabel = New-Object System.Windows.Forms.Label
    $DirLabel.Text = "Destination Directory:"
    $DirLabel.Location = New-Object System.Drawing.Point(26, 95)
    $DirLabel.Size = New-Object System.Drawing.Size(150, 20)
    $Form.Controls.Add($DirLabel)

    $DirBox = New-Object System.Windows.Forms.TextBox
    $DirBox.Text = $TargetDir
    $DirBox.Location = New-Object System.Drawing.Point(26, 120)
    $DirBox.Size = New-Object System.Drawing.Size(450, 24)
    $Form.Controls.Add($DirBox)

    $ChkDesktop = New-Object System.Windows.Forms.CheckBox
    $ChkDesktop.Text = "Create Desktop Shortcut"
    $ChkDesktop.Checked = (-not $NoDesktopShortcut)
    $ChkDesktop.Location = New-Object System.Drawing.Point(30, 160)
    $ChkDesktop.Size = New-Object System.Drawing.Size(300, 24)
    $Form.Controls.Add($ChkDesktop)

    $ChkStartMenu = New-Object System.Windows.Forms.CheckBox
    $ChkStartMenu.Text = "Create Start Menu Folder & Shortcuts"
    $ChkStartMenu.Checked = (-not $NoStartMenuShortcut)
    $ChkStartMenu.Location = New-Object System.Drawing.Point(30, 190)
    $ChkStartMenu.Size = New-Object System.Drawing.Size(300, 24)
    $Form.Controls.Add($ChkStartMenu)

    $ChkAutostart = New-Object System.Windows.Forms.CheckBox
    $ChkAutostart.Text = "Start automatically on Windows sign-in"
    $ChkAutostart.Checked = $EnableAutostart
    $ChkAutostart.Location = New-Object System.Drawing.Point(30, 220)
    $ChkAutostart.Size = New-Object System.Drawing.Size(300, 24)
    $Form.Controls.Add($ChkAutostart)

    $ChkLaunch = New-Object System.Windows.Forms.CheckBox
    $ChkLaunch.Text = "Launch $ProjectName when setup finishes"
    $ChkLaunch.Checked = (-not $NoLaunch)
    $ChkLaunch.Location = New-Object System.Drawing.Point(30, 250)
    $ChkLaunch.Size = New-Object System.Drawing.Size(300, 24)
    $Form.Controls.Add($ChkLaunch)

    $BtnInstall = New-Object System.Windows.Forms.Button
    $BtnInstall.Text = "Install Now"
    $BtnInstall.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
    $BtnInstall.Location = New-Object System.Drawing.Point(250, 310)
    $BtnInstall.Size = New-Object System.Drawing.Size(110, 34)
    $BtnInstall.DialogResult = [System.Windows.Forms.DialogResult]::OK
    $Form.Controls.Add($BtnInstall)

    $BtnCancel = New-Object System.Windows.Forms.Button
    $BtnCancel.Text = "Cancel"
    $BtnCancel.Location = New-Object System.Drawing.Point(370, 310)
    $BtnCancel.Size = New-Object System.Drawing.Size(100, 34)
    $BtnCancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $Form.Controls.Add($BtnCancel)

    $Result = $Form.ShowDialog()
    if ($Result -eq [System.Windows.Forms.DialogResult]::OK) {
        Invoke-Installation `
            -DestDir $DirBox.Text `
            -CreateDesktop $ChkDesktop.Checked `
            -CreateStartMenu $ChkStartMenu.Checked `
            -SetPath $AddPath `
            -SetAutostart $ChkAutostart.Checked `
            -LaunchApp $ChkLaunch.Checked
    }
} catch {
    Write-Warning "Windows Forms unavailable. Falling back to console installation."
    Invoke-Installation `
        -DestDir $TargetDir `
        -CreateDesktop (-not $NoDesktopShortcut) `
        -CreateStartMenu (-not $NoStartMenuShortcut) `
        -SetPath $AddPath `
        -SetAutostart $EnableAutostart `
        -LaunchApp (-not $NoLaunch)
}
