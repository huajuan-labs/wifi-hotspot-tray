#requires -Version 5.1
<#
.SYNOPSIS
    在当前这台电脑上装好 WiFi 热点工具的快捷方式和图标。

.DESCRIPTION
    只是创建快捷方式，不改动系统设置、不写注册表。
    需要卸载时用 -Uninstall，会把创建出来的快捷方式删掉，代码文件保持不动。

.EXAMPLE
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\install.ps1

.EXAMPLE
    # 顺带把托盘图标和热点本身都设成开机自启
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\install.ps1 -WithAutoStart -WithAutoHotspot

.EXAMPLE
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\install.ps1 -Uninstall
#>
[CmdletBinding()]
param(
    [switch]$Uninstall,
    [switch]$WithAutoStart,
    [switch]$WithAutoHotspot
)

$ErrorActionPreference = 'Stop'

$DesktopDir = [Environment]::GetFolderPath('Desktop')
$StartupDir = [Environment]::GetFolderPath('Startup')
$PowerShellExe = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"

$HotspotScript = Join-Path $PSScriptRoot 'hotspot.ps1'
$TrayScript = Join-Path $PSScriptRoot 'HotspotTray.ps1'

$DesktopHotspotLnk = Join-Path $DesktopDir '开启WiFi热点.lnk'
$DesktopTrayLnk = Join-Path $DesktopDir 'WiFi热点控制台.lnk'
$StartupTrayLnk = Join-Path $StartupDir 'WiFi热点控制台.lnk'
$StartupHotspotLnk = Join-Path $StartupDir 'WiFi热点-开机自动开启.lnk'

function New-Shortcut {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Arguments,
        [Parameter(Mandatory)][string]$Description
    )
    $shell = New-Object -ComObject WScript.Shell
    $lnk = $shell.CreateShortcut($Path)
    $lnk.TargetPath = $PowerShellExe
    $lnk.Arguments = $Arguments
    $lnk.WorkingDirectory = $PSScriptRoot
    $lnk.WindowStyle = 7
    $lnk.Description = $Description

    $icon = Join-Path $PSScriptRoot 'hotspot-on.ico'
    if (Test-Path -LiteralPath $icon) { $lnk.IconLocation = "$icon,0" }
    else { $lnk.IconLocation = "$env:SystemRoot\System32\netshell.dll,0" }

    $lnk.Save()
}

function Remove-Shortcut {
    param([Parameter(Mandatory)][string]$Path)
    if (Test-Path -LiteralPath $Path) {
        Remove-Item -LiteralPath $Path -Force
        Write-Host "已删除 $Path"
    }
}

if ($Uninstall) {
    Remove-Shortcut -Path $DesktopHotspotLnk
    Remove-Shortcut -Path $DesktopTrayLnk
    Remove-Shortcut -Path $StartupTrayLnk
    Remove-Shortcut -Path $StartupHotspotLnk
    Write-Host '卸载完成，代码文件仍然保留在本目录。'
    return
}

foreach ($required in @($HotspotScript, $TrayScript)) {
    if (-not (Test-Path -LiteralPath $required)) {
        throw "缺少必需文件：$required"
    }
}

# 先生成图标，快捷方式才能引用到
& $PowerShellExe -NoProfile -ExecutionPolicy Bypass -File $TrayScript -ExportIcons

New-Shortcut -Path $DesktopHotspotLnk -Description '开启 WiFi 热点' `
    -Arguments "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$HotspotScript`" -On"
Write-Host "已创建 $DesktopHotspotLnk"

New-Shortcut -Path $DesktopTrayLnk -Description 'WiFi 热点托盘控制器（常驻右下角通知区）' `
    -Arguments "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$TrayScript`""
Write-Host "已创建 $DesktopTrayLnk"

if ($WithAutoStart) {
    New-Shortcut -Path $StartupTrayLnk -Description 'WiFi 热点托盘控制器（开机自启）' `
        -Arguments "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$TrayScript`""
    Write-Host "已设置开机自启：托盘图标 -> $StartupTrayLnk"
}
else {
    Remove-Shortcut -Path $StartupTrayLnk
}

if ($WithAutoHotspot) {
    New-Shortcut -Path $StartupHotspotLnk -Description '开机后等待网络就绪，然后自动开启 WiFi 热点' `
        -Arguments "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$HotspotScript`" -On -WaitForNetwork"
    Write-Host "已设置开机自启：自动开热点 -> $StartupHotspotLnk"
}
else {
    Remove-Shortcut -Path $StartupHotspotLnk
}

Write-Host ''
Write-Host '安装完成。托盘程序用桌面上的「WiFi热点控制台」启动，右键图标即可开关热点。'
