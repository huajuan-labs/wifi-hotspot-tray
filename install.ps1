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
    [switch]$WithAutoHotspot,
    # 界面语言：auto 跟随系统，zh 中文，en 英文
    [ValidateSet('auto', 'zh', 'en')][string]$Language = 'auto'
)

$ErrorActionPreference = 'Stop'

function Get-InstallStrings {
    param([Parameter(Mandatory)][ValidateSet('zh', 'en')][string]$Lang)

    if ($Lang -eq 'en') {
        return @{
            DesktopHotspot    = 'Turn On WiFi Hotspot.lnk'
            DesktopHotspotDesc = 'Turn the WiFi hotspot on'
            DesktopTray       = 'WiFi Hotspot Tray.lnk'
            DesktopTrayDesc   = 'WiFi Hotspot tray controller'
            StartupTray       = 'WiFi Hotspot Tray.lnk'
            StartupTrayDesc   = 'WiFi Hotspot tray controller (at login)'
            StartupAuto       = 'WiFi Hotspot Auto.lnk'
            StartupAutoDesc   = 'Wait for the network, then enable the WiFi hotspot at login'
            AltNames          = @('开启WiFi热点.lnk', 'WiFi热点控制台.lnk', 'WiFi热点-开机自动开启.lnk')
            Created           = 'Created {0}'
            Deleted           = 'Deleted {0}'
            AutoTraySet       = 'Logon entry set: tray icon -> {0}'
            AutoHotspotSet    = 'Logon entry set: hotspot -> {0}'
            MissingFile       = 'Missing required file: {0}'
            Uninstalled       = 'Uninstall finished. The code files are left in place.'
            Done              = 'Done. Start the tray from the desktop shortcut, then right-click its icon to toggle the hotspot.'
        }
    }

    return @{
        DesktopHotspot    = '开启WiFi热点.lnk'
        DesktopHotspotDesc = '开启 WiFi 热点'
        DesktopTray       = 'WiFi热点控制台.lnk'
        DesktopTrayDesc   = 'WiFi 热点托盘控制器（常驻右下角通知区）'
        StartupTray       = 'WiFi热点控制台.lnk'
        StartupTrayDesc   = 'WiFi 热点托盘控制器（开机自启）'
        StartupAuto       = 'WiFi热点-开机自动开启.lnk'
        StartupAutoDesc   = '开机后等待网络就绪，然后自动开启 WiFi 热点'
        AltNames          = @('Turn On WiFi Hotspot.lnk', 'WiFi Hotspot Tray.lnk', 'WiFi Hotspot Auto.lnk')
        Created           = '已创建 {0}'
        Deleted           = '已删除 {0}'
        AutoTraySet       = '已设置开机自启：托盘图标 -> {0}'
        AutoHotspotSet    = '已设置开机自启：自动开热点 -> {0}'
        MissingFile       = '缺少必需文件：{0}'
        Uninstalled       = '卸载完成，代码文件仍然保留在本目录。'
        Done              = '安装完成。托盘程序用桌面上的「WiFi热点控制台」启动，右键图标即可开关热点。'
    }
}

# 与另外两个脚本同一套判断：不能靠 CurrentUICulture（PowerShell 5.1 会语言回退成 en-US）
function Get-PreferredLanguage {
    try {
        if (-not ([System.Management.Automation.PSTypeName]'HotspotInstaller.SystemLanguage').Type) {
            Add-Type -Namespace HotspotInstaller -Name SystemLanguage -MemberDefinition @'
[DllImport("kernel32.dll")]
public static extern ushort GetUserDefaultUILanguage();
'@
        }
        if (([HotspotInstaller.SystemLanguage]::GetUserDefaultUILanguage() -band 0x3FF) -eq 0x04) { return 'zh' }
        return 'en'
    }
    catch {
        if ([System.Globalization.CultureInfo]::CurrentUICulture.TwoLetterISOLanguageName -eq 'zh') { return 'zh' }
        return 'en'
    }
}

if ($Language -eq 'auto') { $Language = Get-PreferredLanguage }
$T = Get-InstallStrings -Lang $Language

$DesktopDir = [Environment]::GetFolderPath('Desktop')
$StartupDir = [Environment]::GetFolderPath('Startup')
$PowerShellExe = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"

$HotspotScript = Join-Path $PSScriptRoot 'hotspot.ps1'
$TrayScript = Join-Path $PSScriptRoot 'HotspotTray.ps1'

$DesktopHotspotLnk = Join-Path $DesktopDir $T.DesktopHotspot
$DesktopTrayLnk = Join-Path $DesktopDir $T.DesktopTray
$StartupTrayLnk = Join-Path $StartupDir $T.StartupTray
$StartupHotspotLnk = Join-Path $StartupDir $T.StartupAuto

# 切换语言会改变快捷方式文件名，旧名字的文件要一并清掉，否则会留下孤儿
$AltPaths = @(
    ($T.AltNames | ForEach-Object { Join-Path $DesktopDir $_ })
    ($T.AltNames | ForEach-Object { Join-Path $StartupDir $_ })
)

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
        Write-Host ($T.Deleted -f $Path)
    }
}

if ($Uninstall) {
    Remove-Shortcut -Path $DesktopHotspotLnk
    Remove-Shortcut -Path $DesktopTrayLnk
    Remove-Shortcut -Path $StartupTrayLnk
    Remove-Shortcut -Path $StartupHotspotLnk
    foreach ($alt in $AltPaths) { Remove-Shortcut -Path $alt }
    Write-Host $T.Uninstalled
    return
}

foreach ($required in @($HotspotScript, $TrayScript)) {
    if (-not (Test-Path -LiteralPath $required)) {
        throw ($T.MissingFile -f $required)
    }
}

# 先生成图标，快捷方式才能引用到
& $PowerShellExe -NoProfile -ExecutionPolicy Bypass -File $TrayScript -ExportIcons -Language $Language

foreach ($alt in $AltPaths) {
    if (Test-Path -LiteralPath $alt) { Remove-Item -LiteralPath $alt -Force }
}

New-Shortcut -Path $DesktopHotspotLnk -Description $T.DesktopHotspotDesc `
    -Arguments "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$HotspotScript`" -On"
Write-Host ($T.Created -f $DesktopHotspotLnk)

New-Shortcut -Path $DesktopTrayLnk -Description $T.DesktopTrayDesc `
    -Arguments "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$TrayScript`""
Write-Host ($T.Created -f $DesktopTrayLnk)

if ($WithAutoStart) {
    New-Shortcut -Path $StartupTrayLnk -Description $T.StartupTrayDesc `
        -Arguments "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$TrayScript`""
    Write-Host ($T.AutoTraySet -f $StartupTrayLnk)
}
else {
    Remove-Shortcut -Path $StartupTrayLnk
}

if ($WithAutoHotspot) {
    New-Shortcut -Path $StartupHotspotLnk -Description $T.StartupAutoDesc `
        -Arguments "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$HotspotScript`" -On -WaitForNetwork"
    Write-Host ($T.AutoHotspotSet -f $StartupHotspotLnk)
}
else {
    Remove-Shortcut -Path $StartupHotspotLnk
}

Write-Host ''
Write-Host $T.Done
