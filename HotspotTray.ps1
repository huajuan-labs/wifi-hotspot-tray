#requires -Version 5.1
<#
.SYNOPSIS
    WiFi 热点托盘控制器：常驻右下角通知区，右键即可开关热点。

.DESCRIPTION
    用 Windows PowerShell 5.1 运行（WinForms + WinRT，不依赖 .NET SDK 或任何第三方组件）。
    托盘菜单提供开启/关闭、查看连接信息、查看已连设备、开机自启。

.EXAMPLE
    powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File .\HotspotTray.ps1

.EXAMPLE
    # 只做一次自检，不进消息循环
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\HotspotTray.ps1 -SelfTest
#>
[CmdletBinding()]
param(
    [switch]$SelfTest,
    # 把开关两种状态的图标导出成 .ico，方便给快捷方式用
    [switch]$ExportIcons,
    # 生成一张四种状态的预览图，用来确认配色和形状
    [switch]$PreviewIcons,
    # 界面语言：auto 跟随系统，zh 中文，en 英文
    [ValidateSet('auto', 'zh', 'en')][string]$Language = 'auto'
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Runtime.WindowsRuntime | Out-Null

# ---------------------------------------------------------------- 界面语言
# 所有面向用户的文字都从这里取，代码注释仍保持中文。
function Get-HotspotStrings {
    param([Parameter(Mandatory)][ValidateSet('zh', 'en')][string]$Lang)

    if ($Lang -eq 'en') {
        return @{
            NotifyTitle        = 'WiFi Hotspot'
            MenuOn             = 'Turn hotspot on'
            MenuOff            = 'Turn hotspot off'
            MenuStatusInit     = 'Status: querying…'
            MenuInfo           = 'Connection details…'
            MenuAutoTray       = 'Start tray at login'
            MenuAutoHotspot    = 'Enable hotspot at login'
            MenuExit           = 'Exit'
            StatusFormat       = 'Status: {0} ({1}/{2} clients)'
            StatusUnreadable   = 'Status: unavailable'
            StateOn            = 'on'
            StateOff           = 'off'
            TooltipFormat      = "WiFi Hotspot: {0}`n{1}"
            BalloonOn          = 'Hotspot is on. Devices can now find and join it.'
            BalloonOff         = 'Hotspot is off.'
            BalloonFailed      = '{0} failed: {1}'
            ActionOn           = 'Enabling'
            ActionOff          = 'Disabling'
            InfoTitle          = 'WiFi Hotspot connection details'
            InfoState          = 'State: {0}'
            InfoSsid           = 'Network name: {0}'
            InfoPassphrase     = 'secret'
            InfoUpstream       = 'Shared from: {0}'
            InfoClients        = 'Clients: {0}/{1}'
            InfoClientList     = 'Connected devices:'
            InfoReadFailed     = 'Could not read status: {0}'
            LogStarted         = 'Tray app started'
            LogStopped         = 'Tray app stopped'
            LogTimeoutOff      = 'Disabled the no-client auto-off timeout'
            LogTimeoutFailed   = 'Could not disable the timeout: {0}'
            LogSetHotspot      = 'Set-Hotspot target={0} result={1}'
            LogRefreshFailed   = 'Status refresh failed: {0}'
            LogStartupAdded    = 'Added logon shortcut: {0}'
            LogStartupRemoved  = 'Removed logon shortcut'
            LogStartupFailed   = 'Could not change logon shortcut: {0}'
            LogAutoAdded       = 'Added auto-hotspot logon shortcut: {0}'
            LogAutoRemoved     = 'Removed auto-hotspot logon shortcut'
            LogAutoFailed      = 'Could not change auto-hotspot shortcut: {0}'
            LogThemeLoaded     = 'Loaded custom palette: {0}'
            LogThemeFailed     = 'Palette file unreadable, using defaults: {0}'
            LogIconFailed      = 'Custom icon failed to load {0}: {1}'
            LogIconExportFailed = 'Icon export failed: {0}'
            LogExit            = 'User exited the tray app'
            ErrNoInternet      = 'No active Internet connection.'
            ErrToggleFailed    = 'Operation did not take effect; state is still {0}. Check that the Wi-Fi radio is on.'
            ShortcutTray       = 'WiFi Hotspot Tray.lnk'
            ShortcutTrayDesc   = 'WiFi Hotspot tray controller'
            ShortcutAuto       = 'WiFi Hotspot Auto.lnk'
            ShortcutAutoDesc   = 'Wait for the network, then enable the WiFi hotspot at login'
            AltShortcutTray    = 'WiFi热点控制台.lnk'
            AltShortcutAuto    = 'WiFi热点-开机自动开启.lnk'
            SelfTestDone       = 'Self-test: icon, menu and status read all completed.'
            IconLineFmt        = 'icon {0,-11} {1}x{2}'
            Exported           = 'Exported {0}'
        }
    }

    return @{
        NotifyTitle        = 'WiFi 热点'
        MenuOn             = '开启热点'
        MenuOff            = '关闭热点'
        MenuStatusInit     = '状态：查询中…'
        MenuInfo           = '显示连接信息…'
        MenuAutoTray       = '开机自动启动'
        MenuAutoHotspot    = '开机自动开启热点'
        MenuExit           = '退出'
        StatusFormat       = '状态：{0}（{1}/{2} 台设备）'
        StatusUnreadable   = '状态：读取失败'
        StateOn            = '已开启'
        StateOff           = '已关闭'
        TooltipFormat      = "WiFi 热点：{0}`n{1}"
        BalloonOn          = '已开启，设备可以搜索并连接了。'
        BalloonOff         = '已关闭。'
        BalloonFailed      = '{0}失败：{1}'
        ActionOn           = '开启'
        ActionOff          = '关闭'
        InfoTitle          = 'WiFi 热点连接信息'
        InfoState          = '状态：{0}'
        InfoSsid           = '网络名称：{0}'
        InfoPassphrase     = '密码：{0}'
        InfoUpstream       = '共享来源：{0}'
        InfoClients        = '已连接设备：{0}/{1}'
        InfoClientList     = '已连接设备列表：'
        InfoReadFailed     = '读取失败：{0}'
        LogStarted         = '托盘程序启动'
        LogStopped         = '托盘程序结束'
        LogTimeoutOff      = '已关闭「无设备连接自动断开」'
        LogTimeoutFailed   = '关闭超时失败: {0}'
        LogSetHotspot      = 'Set-Hotspot 目标={0} 结果={1}'
        LogRefreshFailed   = '刷新状态失败: {0}'
        LogStartupAdded    = '已添加开机自启: {0}'
        LogStartupRemoved  = '已移除开机自启'
        LogStartupFailed   = '设置开机自启失败: {0}'
        LogAutoAdded       = '已添加开机自动开热点: {0}'
        LogAutoRemoved     = '已移除开机自动开热点'
        LogAutoFailed      = '设置开机自动开热点失败: {0}'
        LogThemeLoaded     = '已加载自定义配色: {0}'
        LogThemeFailed     = '配色文件读取失败，改用默认配色: {0}'
        LogIconFailed      = '自定义图标加载失败 {0} : {1}'
        LogIconExportFailed = '导出图标失败: {0}'
        LogExit            = '用户退出托盘程序'
        ErrNoInternet      = '当前没有活动的 Internet 连接。'
        ErrToggleFailed    = '操作未生效，当前状态仍为 {0}。请确认 Wi-Fi 无线电已打开。'
        ShortcutTray       = 'WiFi热点控制台.lnk'
        ShortcutTrayDesc   = 'WiFi 热点托盘控制器'
        ShortcutAuto       = 'WiFi热点-开机自动开启.lnk'
        ShortcutAutoDesc   = '开机后等待网络就绪，然后自动开启 WiFi 热点'
        AltShortcutTray    = 'WiFi Hotspot Tray.lnk'
        AltShortcutAuto    = 'WiFi Hotspot Auto.lnk'
        SelfTestDone       = '自检：图标、菜单、状态读取均已完成。'
        IconLineFmt        = '图标 {0,-11} 尺寸 {1}x{2}'
        Exported           = '已导出 {0}'
    }
}

# 注意：不能用 CurrentUICulture 判断。Windows PowerShell 5.1 没有中文 UI 资源，
# 系统会对它做语言回退，进程内读到的往往是 en-US，而用户其实用的是中文系统。
# GetUserDefaultUILanguage 返回的是用户真实的首选界面语言。
function Get-PreferredLanguage {
    try {
        if (-not ([System.Management.Automation.PSTypeName]'HotspotTray.SystemLanguage').Type) {
            Add-Type -Namespace HotspotTray -Name SystemLanguage -MemberDefinition @'
[DllImport("kernel32.dll")]
public static extern ushort GetUserDefaultUILanguage();
'@
        }
        # 主语言 ID 4 = 中文（简体、繁体同属 4）
        if (([HotspotTray.SystemLanguage]::GetUserDefaultUILanguage() -band 0x3FF) -eq 0x04) { return 'zh' }
        return 'en'
    }
    catch {
        if ([System.Globalization.CultureInfo]::CurrentUICulture.TwoLetterISOLanguageName -eq 'zh') { return 'zh' }
        return 'en'
    }
}

if ($Language -eq 'auto') { $Language = Get-PreferredLanguage }
$script:T = Get-HotspotStrings -Lang $Language

$LogPath = Join-Path $PSScriptRoot 'hotspot-tray.log'

function Write-Log {
    param([string]$Message)
    try {
        Add-Content -LiteralPath $LogPath -Value ("[{0}] {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message) -Encoding UTF8
    }
    catch { }
}

function Get-TetheringContext {
    $profile = [Windows.Networking.Connectivity.NetworkInformation, Windows.Networking.Connectivity, ContentType = WindowsRuntime]::GetInternetConnectionProfile()
    if (-not $profile) { throw $script:T.ErrNoInternet }
    [pscustomobject]@{
        Profile = $profile
        Manager = [Windows.Networking.NetworkOperators.NetworkOperatorTetheringManager, Windows.Networking.NetworkOperators, ContentType = WindowsRuntime]::CreateFromConnectionProfile($profile)
    }
}

$managerType = [Windows.Networking.NetworkOperators.NetworkOperatorTetheringManager, Windows.Networking.NetworkOperators, ContentType = WindowsRuntime]

# 「无设备连接超时」不在默认接口上，必须走反射，否则热点 5 分钟就自动关。
function Disable-HotspotTimeout {
    param([Parameter(Mandatory)][object]$Manager)
    try {
        if ($managerType.GetMethod('IsNoConnectionsTimeoutEnabled').Invoke($Manager, @())) {
            $managerType.GetMethod('DisableNoConnectionsTimeout').Invoke($Manager, @()) | Out-Null
            Write-Log $script:T.LogTimeoutOff
        }
    }
    catch {
        Write-Log ($script:T.LogTimeoutFailed -f $_.Exception.Message)
    }
}

function Get-HotspotStatus {
    $ctx = Get-TetheringContext
    $ap = $ctx.Manager.GetCurrentAccessPointConfiguration()
    $clients = @($ctx.Manager.GetTetheringClients())
    [pscustomobject]@{
        State       = $ctx.Manager.TetheringOperationalState.ToString()
        Ssid        = $ap.Ssid
        Passphrase  = $ap.Passphrase
        Clients     = $clients
        ClientCount = $clients.Count
        MaxClients  = $ctx.Manager.MaxClientCount
        Upstream    = $ctx.Profile.ProfileName
    }
}

function Set-Hotspot {
    param([Parameter(Mandatory)][ValidateSet('On', 'Off')][string]$Target)

    $ctx = Get-TetheringContext
    if ($Target -eq 'On') { Disable-HotspotTimeout -Manager $ctx.Manager }

    $current = $ctx.Manager.TetheringOperationalState.ToString()
    if ($current -ne $Target) {
        if ($Target -eq 'On') { $ctx.Manager.StartTetheringAsync() | Out-Null }
        else { $ctx.Manager.StopTetheringAsync() | Out-Null }

        for ($i = 0; $i -lt 24; $i++) {
            Start-Sleep -Milliseconds 250
            if ($ctx.Manager.TetheringOperationalState.ToString() -eq $Target) { break }
        }
    }

    $final = $ctx.Manager.TetheringOperationalState.ToString()
    Write-Log ($script:T.LogSetHotspot -f $Target, $final)
    if ($final -ne $Target) {
        throw ($script:T.ErrToggleFailed -f $final)
    }
    return $final
}

# ---------------------------------------------------------------- 托盘界面

Add-Type -Namespace HotspotTray -Name NativeIcon -MemberDefinition @'
[DllImport("user32.dll", SetLastError = true)]
public static extern bool DestroyIcon(System.IntPtr hIcon);
'@

# 图标是现画的：一道 Wi-Fi 弧 + 状态色。想换配色就改这个文件，想整个换掉就放图片。
$script:IconTheme = [ordered]@{
    On         = '#22C55E'
    Off        = '#94A3B8'
    Slash      = '#EF4444'
    Badge      = '#0EA5E9'
    Transition = '#F59E0B'
}

$ThemePath = Join-Path $PSScriptRoot 'hotspot-icon.json'
if (Test-Path -LiteralPath $ThemePath) {
    try {
        $cfg = Get-Content -LiteralPath $ThemePath -Raw -Encoding UTF8 | ConvertFrom-Json
        foreach ($key in @($script:IconTheme.Keys)) {
            if ($cfg.PSObject.Properties.Name -contains $key) { $script:IconTheme[$key] = $cfg.$key }
        }
        Write-Log ($script:T.LogThemeLoaded -f $ThemePath)
    }
    catch {
        Write-Log ($script:T.LogThemeFailed -f $_.Exception.Message)
    }
}

function ConvertTo-IconColor {
    param(
        [Parameter(Mandatory)][string]$Value,
        [Parameter(Mandatory)][System.Drawing.Color]$Fallback
    )
    try { [System.Drawing.ColorTranslator]::FromHtml($Value) }
    catch { $Fallback }
}

$script:ColorOn = ConvertTo-IconColor -Value $script:IconTheme['On'] -Fallback ([System.Drawing.Color]::FromArgb(34, 197, 94))
$script:ColorOff = ConvertTo-IconColor -Value $script:IconTheme['Off'] -Fallback ([System.Drawing.Color]::FromArgb(148, 163, 184))
$script:ColorSlash = ConvertTo-IconColor -Value $script:IconTheme['Slash'] -Fallback ([System.Drawing.Color]::FromArgb(239, 68, 68))
$script:ColorBadge = ConvertTo-IconColor -Value $script:IconTheme['Badge'] -Fallback ([System.Drawing.Color]::FromArgb(14, 165, 233))
$script:ColorTransition = ConvertTo-IconColor -Value $script:IconTheme['Transition'] -Fallback ([System.Drawing.Color]::FromArgb(245, 158, 11))

function New-HotspotIconBitmap {
    param(
        [Parameter(Mandatory)][ValidateSet('on', 'on-clients', 'off', 'busy')][string]$State,
        [int]$Size = 32
    )

    $bmp = New-Object System.Drawing.Bitmap($Size, $Size, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.Clear([System.Drawing.Color]::Transparent)

    $color = switch ($State) {
        'on' { $script:ColorOn }
        'on-clients' { $script:ColorOn }
        'busy' { $script:ColorTransition }
        default { $script:ColorOff }
    }

    $centerX = $Size / 2.0
    $centerY = $Size * 0.80
    $penWidth = [float]($Size * 0.075)
    $pen = New-Object System.Drawing.Pen($color, $penWidth)
    $pen.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
    $pen.EndCap = [System.Drawing.Drawing2D.LineCap]::Round

    # 三道光弧，从下往上扩散，构成 Wi-Fi 符号
    foreach ($factor in @(0.26, 0.44, 0.62)) {
        $radius = [float]($Size * $factor)
        $rect = New-Object System.Drawing.RectangleF(
            ([float]($centerX - $radius)), ([float]($centerY - $radius)),
            ([float]($radius * 2)), ([float]($radius * 2)))
        $g.DrawArc($pen, $rect, 225, 90)
    }

    # 底部的信号源圆点
    $dotRadius = [float]($Size * 0.075)
    $brush = New-Object System.Drawing.SolidBrush($color)
    $g.FillEllipse($brush,
        ([float]($centerX - $dotRadius)), ([float]($centerY - $dotRadius)),
        ([float]($dotRadius * 2)), ([float]($dotRadius * 2)))

    if ($State -eq 'off') {
        # 关闭状态加一道斜杠，和「开着」一眼能分开
        $slashPen = New-Object System.Drawing.Pen($script:ColorSlash, ([float]($Size * 0.095)))
        $slashPen.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
        $slashPen.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
        $g.DrawLine($slashPen,
            ([float]($Size * 0.20)), ([float]($Size * 0.20)),
            ([float]($Size * 0.80)), ([float]($Size * 0.80)))
        $slashPen.Dispose()
    }

    if ($State -eq 'on-clients') {
        # 有设备连着时右下角点一颗徽标
        $badgeRadius = [float]($Size * 0.145)
        $badgeBrush = New-Object System.Drawing.SolidBrush($script:ColorBadge)
        $badgePen = New-Object System.Drawing.Pen([System.Drawing.Color]::White, [float]($Size * 0.035))
        # 留出描边占的宽度，避免贴边被裁
        $bx = [float]($Size * 0.66)
        $by = [float]($Size * 0.66)
        $g.FillEllipse($badgeBrush, $bx, $by, ([float]($badgeRadius * 2)), ([float]($badgeRadius * 2)))
        $g.DrawEllipse($badgePen, $bx, $by, ([float]($badgeRadius * 2)), ([float]($badgeRadius * 2)))
        $badgeBrush.Dispose()
        $badgePen.Dispose()
    }

    $pen.Dispose()
    $brush.Dispose()
    $g.Dispose()
    return $bmp
}

function Get-CustomStateIcon {
    param([Parameter(Mandatory)][string]$State)
    # 想彻底换掉图标，就在脚本目录放 hotspot-on.ico / hotspot-off.ico（也支持 .png）
    $name = if ($State -eq 'off') { 'hotspot-off' } else { 'hotspot-on' }
    foreach ($ext in @('.ico', '.png')) {
        $path = Join-Path $PSScriptRoot "$name$ext"
        if (-not (Test-Path -LiteralPath $path)) { continue }
        try {
            if ($ext -eq '.ico') {
                return (New-Object System.Drawing.Icon($path)).Clone()
            }
            $img = [System.Drawing.Image]::FromFile($path)
            $hIcon = $img.GetHicon()
            $icon = ([System.Drawing.Icon]::FromHandle($hIcon)).Clone()
            [HotspotTray.NativeIcon]::DestroyIcon($hIcon) | Out-Null
            $img.Dispose()
            return $icon
        }
        catch {
            Write-Log ($script:T.LogIconFailed -f $path, $_.Exception.Message)
        }
    }
    return $null
}

$script:IconCache = @{}

function Get-StateIcon {
    param([Parameter(Mandatory)][string]$State)
    if ($script:IconCache.ContainsKey($State)) { return $script:IconCache[$State] }

    $icon = Get-CustomStateIcon -State $State
    if (-not $icon) {
        $bmp = New-HotspotIconBitmap -State $State -Size 32
        $hIcon = $bmp.GetHicon()
        $icon = ([System.Drawing.Icon]::FromHandle($hIcon)).Clone()
        [HotspotTray.NativeIcon]::DestroyIcon($hIcon) | Out-Null
        $bmp.Dispose()
    }
    $script:IconCache[$State] = $icon
    return $icon
}

function Export-StateIcons {
    foreach ($pair in @(@{ State = 'off'; File = 'hotspot-off.ico' }, @{ State = 'on'; File = 'hotspot-on.ico' })) {
        $bmp = New-HotspotIconBitmap -State $pair.State -Size 64
        $hIcon = $bmp.GetHicon()
        $icon = [System.Drawing.Icon]::FromHandle($hIcon)
        $target = Join-Path $PSScriptRoot $pair.File
        $stream = [System.IO.File]::Create($target)
        $icon.Save($stream)
        $stream.Close()
        $icon.Dispose()
        [HotspotTray.NativeIcon]::DestroyIcon($hIcon) | Out-Null
        $bmp.Dispose()
        Write-Host ($script:T.Exported -f $target)
    }
}

$script:Notify = New-Object System.Windows.Forms.NotifyIcon
$script:Notify.Icon = Get-StateIcon -State 'off'
$script:Notify.Text = $script:T.NotifyTitle

$menu = New-Object System.Windows.Forms.ContextMenuStrip

$itemOn = $menu.Items.Add($script:T.MenuOn)
$itemOff = $menu.Items.Add($script:T.MenuOff)
$menu.Items.Add('-') | Out-Null
$itemStatus = $menu.Items.Add($script:T.MenuStatusInit)
$itemStatus.Enabled = $false
$itemInfo = $menu.Items.Add($script:T.MenuInfo)
$menu.Items.Add('-') | Out-Null
$itemStartup = $menu.Items.Add($script:T.MenuAutoTray)
$itemStartup.CheckOnClick = $true
$itemAutoHotspot = $menu.Items.Add($script:T.MenuAutoHotspot)
$itemAutoHotspot.CheckOnClick = $true
$menu.Items.Add('-') | Out-Null
$itemExit = $menu.Items.Add($script:T.MenuExit)

$StartupDir = [Environment]::GetFolderPath('Startup')
$StartupLnk = Join-Path $StartupDir $script:T.ShortcutTray
$AutoHotspotLnk = Join-Path $StartupDir $script:T.ShortcutAuto
# 切换语言后旧名字的快捷方式会变成孤儿，创建时顺手清掉
$AltStartupLnk = Join-Path $StartupDir $script:T.AltShortcutTray
$AltAutoHotspotLnk = Join-Path $StartupDir $script:T.AltShortcutAuto

function Get-ShortcutIconLocation {
    # 优先用自己画的图标；没有就先导出，导出失败才退回系统图标
    $own = Join-Path $PSScriptRoot 'hotspot-on.ico'
    if (-not (Test-Path -LiteralPath $own)) {
        try { Export-StateIcons } catch { Write-Log ($script:T.LogIconExportFailed -f $_.Exception.Message) }
    }
    if (Test-Path -LiteralPath $own) { return "$own,0" }
    return "$env:SystemRoot\System32\netshell.dll,0"
}

function New-TrayShortcut {
    param([Parameter(Mandatory)][string]$Path)
    $shell = New-Object -ComObject WScript.Shell
    $lnk = $shell.CreateShortcut($Path)
    $lnk.TargetPath = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
    $lnk.Arguments = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$PSCommandPath`""
    $lnk.WorkingDirectory = $PSScriptRoot
    $lnk.WindowStyle = 7
    $lnk.IconLocation = Get-ShortcutIconLocation
    $lnk.Description = $script:T.ShortcutTrayDesc
    $lnk.Save()
}

function New-AutoHotspotShortcut {
    $shell = New-Object -ComObject WScript.Shell
    $lnk = $shell.CreateShortcut($AutoHotspotLnk)
    $lnk.TargetPath = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
    $lnk.Arguments = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$PSScriptRoot\hotspot.ps1`" -On -WaitForNetwork"
    $lnk.WorkingDirectory = $PSScriptRoot
    $lnk.WindowStyle = 7
    $lnk.IconLocation = Get-ShortcutIconLocation
    $lnk.Description = $script:T.ShortcutAutoDesc
    $lnk.Save()
}

function Update-TrayDisplay {
    try {
        $status = Get-HotspotStatus
        $stateText = if ($status.State -eq 'On') { $script:T.StateOn } else { $script:T.StateOff }
        $itemStatus.Text = $script:T.StatusFormat -f $stateText, $status.ClientCount, $status.MaxClients
        $tooltip = $script:T.TooltipFormat -f $stateText, $status.Ssid
        if ($tooltip.Length -gt 63) { $tooltip = $tooltip.Substring(0, 63) }
        $script:Notify.Text = $tooltip

        $iconState = switch ($status.State) {
            'On' { if ($status.ClientCount -gt 0) { 'on-clients' } else { 'on' } }
            'Off' { 'off' }
            default { 'busy' }
        }
        $script:Notify.Icon = Get-StateIcon -State $iconState
    }
    catch {
        $itemStatus.Text = $script:T.StatusUnreadable
        Write-Log ($script:T.LogRefreshFailed -f $_.Exception.Message)
    }
}

$itemOn.add_Click({
        try {
            Set-Hotspot -Target 'On' | Out-Null
            $script:Notify.ShowBalloonTip(3000, $script:T.NotifyTitle, $script:T.BalloonOn, [System.Windows.Forms.ToolTipIcon]::Info)
        }
        catch {
            $script:Notify.ShowBalloonTip(5000, $script:T.NotifyTitle, ($script:T.BalloonFailed -f $script:T.ActionOn, $_.Exception.Message), [System.Windows.Forms.ToolTipIcon]::Error)
        }
        Update-TrayDisplay
    })

$itemOff.add_Click({
        try {
            Set-Hotspot -Target 'Off' | Out-Null
            $script:Notify.ShowBalloonTip(3000, $script:T.NotifyTitle, $script:T.BalloonOff, [System.Windows.Forms.ToolTipIcon]::Info)
        }
        catch {
            $script:Notify.ShowBalloonTip(5000, $script:T.NotifyTitle, ($script:T.BalloonFailed -f $script:T.ActionOff, $_.Exception.Message), [System.Windows.Forms.ToolTipIcon]::Error)
        }
        Update-TrayDisplay
    })

$itemInfo.add_Click({
        try {
            $status = Get-HotspotStatus
            $stateText = if ($status.State -eq 'On') { $script:T.StateOn } else { $script:T.StateOff }
            $lines = @(
                ($script:T.InfoState -f $stateText)
                ($script:T.InfoSsid -f $status.Ssid)
                ($script:T.InfoPassphrase -f $status.Passphrase)
                ($script:T.InfoUpstream -f $status.Upstream)
                ($script:T.InfoClients -f $status.ClientCount, $status.MaxClients)
            )
            if ($status.Clients.Count -gt 0) {
                $lines += ''
                $lines += $script:T.InfoClientList
                foreach ($c in $status.Clients) {
                    $lines += "  · $($c.DisplayName)  $($c.MacAddress)"
                }
            }
            [System.Windows.Forms.MessageBox]::Show(($lines -join [Environment]::NewLine), $script:T.InfoTitle,
                [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
        }
        catch {
            [System.Windows.Forms.MessageBox]::Show(($script:T.InfoReadFailed -f $_.Exception.Message), $script:T.NotifyTitle,
                [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
        }
    })

$itemStartup.add_Click({
        try {
            if ($itemStartup.Checked) {
                New-TrayShortcut -Path $StartupLnk
                if (Test-Path -LiteralPath $AltStartupLnk) { Remove-Item -LiteralPath $AltStartupLnk -Force }
                Write-Log ($script:T.LogStartupAdded -f $StartupLnk)
            }
            elseif (Test-Path -LiteralPath $StartupLnk) {
                Remove-Item -LiteralPath $StartupLnk -Force
                Write-Log $script:T.LogStartupRemoved
            }
        }
        catch {
            Write-Log ($script:T.LogStartupFailed -f $_.Exception.Message)
            $itemStartup.Checked = -not $itemStartup.Checked
        }
    })

$itemExit.add_Click({
        Write-Log $script:T.LogExit
        $script:Notify.Visible = $false
        [System.Windows.Forms.Application]::Exit()
    })

$itemAutoHotspot.add_Click({
        try {
            if ($itemAutoHotspot.Checked) {
                New-AutoHotspotShortcut
                if (Test-Path -LiteralPath $AltAutoHotspotLnk) { Remove-Item -LiteralPath $AltAutoHotspotLnk -Force }
                Write-Log ($script:T.LogAutoAdded -f $AutoHotspotLnk)
            }
            elseif (Test-Path -LiteralPath $AutoHotspotLnk) {
                Remove-Item -LiteralPath $AutoHotspotLnk -Force
                Write-Log $script:T.LogAutoRemoved
            }
        }
        catch {
            Write-Log ($script:T.LogAutoFailed -f $_.Exception.Message)
            $itemAutoHotspot.Checked = -not $itemAutoHotspot.Checked
        }
    })

$script:Notify.add_MouseDoubleClick({
        try {
            $ctx = Get-TetheringContext
            $target = if ($ctx.Manager.TetheringOperationalState.ToString() -eq 'On') { 'Off' } else { 'On' }
            Set-Hotspot -Target $target | Out-Null
        }
        catch {
            $script:Notify.ShowBalloonTip(5000, $script:T.NotifyTitle, $_.Exception.Message, [System.Windows.Forms.ToolTipIcon]::Error)
        }
        Update-TrayDisplay
    })

$script:Notify.ContextMenuStrip = $menu
$itemStartup.Checked = (Test-Path -LiteralPath $StartupLnk) -or (Test-Path -LiteralPath $AltStartupLnk)
$itemAutoHotspot.Checked = (Test-Path -LiteralPath $AutoHotspotLnk) -or (Test-Path -LiteralPath $AltAutoHotspotLnk)
Update-TrayDisplay

$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 3000
$timer.add_Tick({ Update-TrayDisplay })
$timer.Start()

$script:Notify.Visible = $true
Write-Log $script:T.LogStarted

if ($SelfTest) {
    Write-Host $script:T.SelfTestDone
    Write-Host ("Language = $Language")
    (Get-HotspotStatus) | Format-List
    foreach ($state in @('off', 'on', 'on-clients')) {
        $candidate = Get-StateIcon -State $state
        Write-Host ($script:T.IconLineFmt -f $state, $candidate.Width, $candidate.Height)
    }
    $timer.Stop()
    $script:Notify.Visible = $false
    $script:Notify.Dispose()
    return
}

if ($ExportIcons) {
    Export-StateIcons
    $timer.Stop()
    $script:Notify.Visible = $false
    $script:Notify.Dispose()
    return
}

if ($PreviewIcons) {
    $size = 128
    $gap = 14
    $labelHeight = 34
    $states = @(
        @{ State = 'off'; Label = 'Off' }
        @{ State = 'on'; Label = 'On' }
        @{ State = 'on-clients'; Label = 'On + client' }
        @{ State = 'busy'; Label = 'Switching' }
    )
    $tileWidth = $size + $gap
    $totalWidth = $tileWidth * $states.Count + $gap
    $totalHeight = $size + $labelHeight + $gap * 2
    $preview = New-Object System.Drawing.Bitmap($totalWidth, $totalHeight, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g = [System.Drawing.Graphics]::FromImage($preview)
    $g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::ClearTypeGridFit
    # 深色底，方便看清浅色描边
    $g.Clear([System.Drawing.Color]::FromArgb(32, 32, 36))
    $font = New-Object System.Drawing.Font('Segoe UI', 13)
    $labelBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(200, 200, 208))
    $labelFormat = New-Object System.Drawing.StringFormat
    $labelFormat.Alignment = [System.Drawing.StringAlignment]::Center
    $index = 0
    foreach ($item in $states) {
        $state = $item.State
        $left = $gap + $index * $tileWidth
        $frameBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(48, 48, 54))
        $g.FillRectangle($frameBrush, $left, $gap, $size, $size)
        $frameBrush.Dispose()
        $tile = New-HotspotIconBitmap -State $state -Size $size
        $minX = $size; $maxX = -1; $minY = $size; $maxY = -1
        for ($y = 0; $y -lt $size; $y++) {
            for ($x = 0; $x -lt $size; $x++) {
                if ($tile.GetPixel($x, $y).A -gt 8) {
                    if ($x -lt $minX) { $minX = $x }
                    if ($x -gt $maxX) { $maxX = $x }
                    if ($y -lt $minY) { $minY = $y }
                    if ($y -gt $maxY) { $maxY = $y }
                }
            }
        }
        $touch = @()
        if ($minX -le 0) { $touch += '左' }
        if ($maxX -ge $size - 1) { $touch += '右' }
        if ($minY -le 0) { $touch += '上' }
        if ($maxY -ge $size - 1) { $touch += '下' }
        Write-Host ("{0,-11} 边界 x:{1}-{2} y:{3}-{4} {5}" -f $state, $minX, $maxX, $minY, $maxY,
            $(if ($touch) { "被裁切($($touch -join '/'))" } else { '完整' }))
        $g.DrawImage($tile, $left, $gap, $size, $size)
        $labelRect = New-Object System.Drawing.RectangleF($left, ($gap + $size + 6), $size, $labelHeight)
        $g.DrawString($item.Label, $font, $labelBrush, $labelRect, $labelFormat)
        $tile.Dispose()
        $index++
    }
    $font.Dispose(); $labelBrush.Dispose(); $labelFormat.Dispose()
    $g.Dispose()
    $docsDir = Join-Path $PSScriptRoot 'docs'
    if (-not (Test-Path -LiteralPath $docsDir)) { New-Item -ItemType Directory -Path $docsDir | Out-Null }
    $out = Join-Path $docsDir 'tray-icons.png'
    $preview.Save($out, [System.Drawing.Imaging.ImageFormat]::Png)
    $preview.Dispose()
    Write-Host "已生成预览: $out"
    $timer.Stop()
    $script:Notify.Visible = $false
    $script:Notify.Dispose()
    return
}

[System.Windows.Forms.Application]::Run()

$timer.Stop()
$script:Notify.Visible = $false
$script:Notify.Dispose()
Write-Log $script:T.LogStopped
