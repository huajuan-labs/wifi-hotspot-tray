#requires -Version 5.1
<#
.SYNOPSIS
    控制 Windows 内置移动热点（Wi-Fi Direct / WinRT 热点 API）。

.DESCRIPTION
    这台机器的 Intel Wireless-AC 9560 驱动不支持旧的承载网络
    （netsh wlan set hostednetwork 一类），因此必须走这条新 API 路径。
    WinRT 异步投影依赖 System.Runtime.WindowsRuntime，请用
    Windows PowerShell 5.1 运行，不要在 PowerShell 7 里跑。

.EXAMPLE
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\hotspot.ps1 -Status

.EXAMPLE
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\hotspot.ps1 -On

.EXAMPLE
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\hotspot.ps1 -On -Ssid MyAP -Passphrase 'ZINFOID_07Q'

.EXAMPLE
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\hotspot.ps1 -Off

.EXAMPLE
    # 守护模式：被系统的省电策略关掉后自动重新开启，Ctrl+C 退出
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\hotspot.ps1 -Watch
#>
[CmdletBinding(DefaultParameterSetName = 'Status')]
param(
    [Parameter(ParameterSetName = 'On', Mandatory = $true)][switch]$On,
    [Parameter(ParameterSetName = 'Off', Mandatory = $true)][switch]$Off,
    [Parameter(ParameterSetName = 'Status', Mandatory = $true)][switch]$Status,
    [Parameter(ParameterSetName = 'Watch', Mandatory = $true)][switch]$Watch,
    [Parameter(ParameterSetName = 'Watch')][int]$IntervalSeconds = 15,
    [Parameter(ParameterSetName = 'On')][string]$Ssid,
    [Parameter(ParameterSetName = 'On')][string]$Passphrase,
    # 开机自启场景：登录时网络可能还没就绪，先等一会儿再开热点。
    [Parameter(ParameterSetName = 'On')][switch]$WaitForNetwork,
    [Parameter(ParameterSetName = 'On')][int]$NetworkTimeoutSeconds = 180
)

# 双击桌面快捷方式时窗口一闪而过，用户会看不出到底成没成功。
# 给 -On 一个短暂的停留时间，让结果能被看见。
$AutoCloseDelaySeconds = 5

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Runtime.WindowsRuntime | Out-Null

# WinRT 的 IAsyncAction 在 PowerShell 里没有 GetAwaiter，需要手工包成 Task。
$asTaskAction = ([System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object {
        $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and
        $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncAction'
    })[0]

function Wait-WinRtAction {
    param([Parameter(Mandatory)][object]$Action)
    $task = $asTaskAction.Invoke($null, @($Action))
    $task.Wait()
}

# StartTetheringAsync / StopTetheringAsync 返回的运行时类在 PowerShell 5.1 里
# 没法按类型名解析，所以不取返回值，直接轮询状态判断是否生效。
function Wait-HotspotState {
    param(
        [Parameter(Mandatory)][object]$Manager,
        [Parameter(Mandatory)][string]$Target,
        [int]$TimeoutSeconds = 25
    )
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    do {
        $state = $Manager.TetheringOperationalState.ToString()
        if ($state -eq $Target) { return $state }
        Start-Sleep -Milliseconds 500
    } while ((Get-Date) -lt $deadline)
    return $Manager.TetheringOperationalState.ToString()
}

function Get-TetheringContext {
    $profile = [Windows.Networking.Connectivity.NetworkInformation, Windows.Networking.Connectivity, ContentType = WindowsRuntime]::GetInternetConnectionProfile()
    if (-not $profile) {
        throw '当前没有活动的 Internet 连接，无法定位热点管理器。'
    }
    [pscustomobject]@{
        Profile = $profile
        Manager = [Windows.Networking.NetworkOperators.NetworkOperatorTetheringManager, Windows.Networking.NetworkOperators, ContentType = WindowsRuntime]::CreateFromConnectionProfile($profile)
    }
}

# 开机自启时 WLAN 可能还没连上，这里先等到有 Internet 连接再继续。
if ($WaitForNetwork) {
    $deadline = (Get-Date).AddSeconds($NetworkTimeoutSeconds)
    Write-Host "等待网络就绪（最多 $NetworkTimeoutSeconds 秒）…"
    while ((Get-Date) -lt $deadline) {
        if ([Windows.Networking.Connectivity.NetworkInformation, Windows.Networking.Connectivity, ContentType = WindowsRuntime]::GetInternetConnectionProfile()) {
            Write-Host '网络已就绪。'
            break
        }
        Start-Sleep -Seconds 5
    }
}

$context = Get-TetheringContext
$connectionProfile = $context.Profile
$manager = $context.Manager
$managerType = [Windows.Networking.NetworkOperators.NetworkOperatorTetheringManager, Windows.Networking.NetworkOperators, ContentType = WindowsRuntime]
$apType = [Windows.Networking.NetworkOperators.NetworkOperatorTetheringAccessPointConfiguration, Windows.Networking.NetworkOperators, ContentType = WindowsRuntime]

# 「无设备连接时自动关闭热点」这个开关（默认开启，超时约 5 分钟）不在默认接口上，
# PowerShell 直接点不出来，必须走反射。注册表里的落地值是 icssvc\Settings\PeerlessTimeoutEnabled。
function Get-NoConnectionsTimeout {
    param([Parameter(Mandatory)][object]$Manager)
    $managerType.GetMethod('IsNoConnectionsTimeoutEnabled').Invoke($Manager, @())
}

function Disable-NoConnectionsTimeout {
    param([Parameter(Mandatory)][object]$Manager)
    if (Get-NoConnectionsTimeout -Manager $Manager) {
        $managerType.GetMethod('DisableNoConnectionsTimeout').Invoke($Manager, @()) | Out-Null
    }
}

function Show-HotspotStatus {
    param($Manager)
    $ap = $Manager.GetCurrentAccessPointConfiguration()
    $clients = $Manager.GetTetheringClients() | ForEach-Object {
        [pscustomobject]@{
            Name   = $_.DisplayName
            MAC    = $_.MacAddress
            Hostnames = ($_.HostNames | ForEach-Object { $_.RawName }) -join ', '
        }
    }
    [pscustomobject]@{
        State               = $Manager.TetheringOperationalState
        Ssid                = $ap.Ssid
        Passphrase          = $ap.Passphrase
        Band                = $ap.Band
        Clients             = $Manager.ClientCount
        MaxClients          = $Manager.MaxClientCount
        NoConnectionsTimeout= Get-NoConnectionsTimeout -Manager $Manager
        Upstream            = $connectionProfile.ProfileName
    }
    if ($clients) {
        Write-Host '已连接设备：'
        foreach ($c in $clients) {
            $hosts = ($c.Hostnames | Where-Object { $_ }) -join ', '
            Write-Host ("  · {0}  {1}{2}" -f $c.Name, $c.MAC, $(if ($hosts) { "  ($hosts)" } else { '' }))
        }
    }
}

switch ($PSCmdlet.ParameterSetName) {
    'Status' {
        Show-HotspotStatus -Manager $manager | Format-List
    }
    'On' {
        if ($Ssid -or $Passphrase) {
            if ($Passphrase -and $Passphrase.Length -lt 8) {
                throw '热点密码至少 8 位。'
            }
            $ap = [Activator]::CreateInstance($apType)
            if ($Ssid) { $ap.Ssid = $Ssid }
            if ($Passphrase) { $ap.Passphrase = $Passphrase }
            Wait-WinRtAction -Action $manager.ConfigureAccessPointAsync($ap)
        }

        Disable-NoConnectionsTimeout -Manager $manager

        if ($manager.TetheringOperationalState -eq 'On') {
            Write-Host '热点已在运行，无需重复开启。'
        }
        else {
            $manager.StartTetheringAsync() | Out-Null
            if ((Wait-HotspotState -Manager $manager -Target 'On') -ne 'On') {
                throw '开启失败。请确认 Wi-Fi 无线电已打开，且「设置 → 网络和 Internet → 移动热点」里的共享源可用。'
            }
        }
        Show-HotspotStatus -Manager $manager | Format-List
        if ($Host.Name -eq 'ConsoleHost') {
            Write-Host ''
            Write-Host "$AutoCloseDelaySeconds 秒后自动关闭窗口，按 Ctrl+C 立即退出。"
            Start-Sleep -Seconds $AutoCloseDelaySeconds
        }
    }
    'Off' {
        if ($manager.TetheringOperationalState -eq 'Off') {
            Write-Host '热点本来就是关闭的。'
        }
        else {
            $manager.StopTetheringAsync() | Out-Null
            if ((Wait-HotspotState -Manager $manager -Target 'Off') -ne 'Off') {
                throw '关闭失败，热点仍处于活动状态。'
            }
        }
        Show-HotspotStatus -Manager $manager | Format-List
    }
    'Watch' {
        # Windows 默认在「无设备连接」时自动关闭移动热点，守护模式负责把它拉回来。
        Write-Host "守护模式已启动，每 $IntervalSeconds 秒检查一次。按 Ctrl+C 退出。"
        while ($true) {
            $fresh = Get-TetheringContext
            if ($fresh.Manager.TetheringOperationalState -ne 'On') {
                Write-Host "[$(Get-Date -Format 'HH:mm:ss')] 热点已关闭，重新开启…"
                Disable-NoConnectionsTimeout -Manager $fresh.Manager
                $fresh.Manager.StartTetheringAsync() | Out-Null
                $state = Wait-HotspotState -Manager $fresh.Manager -Target 'On' -TimeoutSeconds 20
                Write-Host "[$(Get-Date -Format 'HH:mm:ss')] 当前状态：$state"
            }
            Start-Sleep -Seconds $IntervalSeconds
        }
    }
}
