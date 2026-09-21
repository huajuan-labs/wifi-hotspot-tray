# WiFi 热点托盘工具

[English](README.md) | **简体中文**

![平台](https://img.shields.io/badge/platform-Windows%2010%20%7C%2011-0078D6)
![PowerShell](https://img.shields.io/badge/PowerShell-5.1-5391FE)
![许可](https://img.shields.io/badge/license-MIT-green)

把 Windows 内置的「移动热点」变成一个常驻托盘的小图标：右键开关、双击切换、实时显示连接数。同时修掉那个悄悄毁掉这个功能的毛病——**没有任何设备连接时，Windows 会在 5 分钟后把热点关掉。**

不依赖 .NET SDK、Node.js 或任何第三方二进制，只用系统自带的 Windows PowerShell 和 WinForms。

![托盘图标状态](docs/tray-icons.png)

## 为什么需要它

如果你试过用笔记本分享 Wi-Fi，大概率撞过下面两堵墙之一。

**现成工具基本都建在一个已经死掉的接口上。** 经典的 `netsh wlan set hostednetwork` 那一套（以及基于它的所有图形工具，VirtualRouter、mHotspot、各种批处理脚本）依赖老式承载网络能力。Intel 等厂商多年前就从驱动里把它移除了。你可以自己确认：

```powershell
netsh wlan show drivers | Select-String 'Hosted network supported'
```

如果输出 `No`，那些工具在你的机器上一定失败。它们没写错，是地基没了。本项目改用现代的移动热点接口，所以在它们跑不动的地方能跑。

**就算能用，热点也会自己关。** 没有客户端连接时，Windows 大约 5 分钟后就把它关掉。你开完热点走到手机旁边，它已经没了。控制这个行为的开关不在默认 COM 接口上，PowerShell 直接调用会报「不包含该方法」——本项目用反射拿到它，并永久关掉。

## 环境要求

- Windows 10 或 11
- **Windows PowerShell 5.1**，即 `%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe`
- 支持 Wi-Fi Direct 的无线网卡（近十年的网卡都可以）
- 不需要管理员权限

> **不要在 PowerShell 7（`pwsh`）里运行。** WinRT 异步投影依赖 `System.Runtime.WindowsRuntime`，PS7 不提供，调用会失败。`install.ps1` 创建的快捷方式已经指向正确的引擎。

## 界面语言

三个脚本都会自动跟随 Windows 的显示语言：中文系统输出中文，其他语言输出英文。也可以强制指定：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\hotspot.ps1 -Status -Language en
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\install.ps1 -Language en -WithAutoStart
```

语言判断用的是 Win32 的 `GetUserDefaultUILanguage`，而不是 .NET 的 `CurrentUICulture`。原因是 Windows PowerShell 5.1 不带中文 UI 资源，系统会对它做语言回退，进程内读到的往往是 `en-US`——用它判断会让中文系统拿到英文界面。

## 快速开始

```powershell
git clone https://github.com/huajuan-labs/wifi-hotspot-tray.git
cd wifi-hotspot-tray

# 创建桌面快捷方式并生成图标
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\install.ps1

# 启动托盘程序
powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File .\HotspotTray.ps1
```

然后右键托盘图标即可。图标一开始可能被收进溢出区（`^`），拖到任务栏上就能固定。

如果还想让图标开机自动出现、热点也自动打开：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\install.ps1 -WithAutoStart -WithAutoHotspot
```

自启项会先等网络就绪（最多 180 秒）再开热点，因为登录那一刻 Wi-Fi 通常还没连上。

## 托盘菜单

```
开启热点
关闭热点
────────────
状态：已开启（0/8 台设备）      ← 每 3 秒刷新
显示连接信息…                    ← 网络名称、密码、已连设备
────────────
开机自动启动                     ← 只恢复托盘图标
开机自动开启热点                 ← 连热点一起打开
────────────
退出
```

图标会随状态变化：关闭是灰色加红斜杠，开启是绿色，有设备连接时多一颗蓝点，切换过程是橙色。

## 命令行

`hotspot.ps1` 能做完托盘能做的所有事，只是没有界面：

| 参数 | 作用 |
|---|---|
| `-Status` | 查看状态、网络名称、密码、频段和已连设备 |
| `-On` | 开启热点（同时关掉自动断开超时） |
| `-Off` | 关闭热点 |
| `-On -Ssid X -Passphrase Y` | 用新的名称和密码开启 |
| `-On -WaitForNetwork` | 先等网络就绪再开，默认最多等 180 秒（用 `-NetworkTimeoutSeconds` 调整） |
| `-Watch` | 守护模式：被关掉就自动拉回来，Ctrl+C 退出 |
| `-Language auto\|zh\|en` | 指定界面语言，默认 `auto`（跟随系统） |

所有命令都必须用 5.1 引擎：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\hotspot.ps1 -Status
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\hotspot.ps1 -On
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\hotspot.ps1 -Off
```

## 实现原理

**开与关**走的是现代的热点接口，不是那个已废弃的承载网络接口：

```powershell
[Windows.Networking.NetworkOperators.NetworkOperatorTetheringManager, Windows.Networking.NetworkOperators, ContentType = WindowsRuntime]::CreateFromConnectionProfile($profile)
```

**关闭 5 分钟超时**必须用反射，因为 `NoConnectionsTimeout` 定义在 `INetworkOperatorTetheringManager2` 上，而 PowerShell 绑定的是更早的默认接口：

```powershell
$managerType.GetMethod('IsNoConnectionsTimeoutEnabled').Invoke($manager, @())
$managerType.GetMethod('DisableNoConnectionsTimeout').Invoke($manager, @())
```

这个设置会落到注册表，重启依然有效：

```
HKLM\SYSTEM\CurrentControlSet\Services\icssvc\Settings\PeerlessTimeoutEnabled = 0
```

**想确认它是不是又掉了？** 这两条日志能看出来：

```powershell
Get-WinEvent -LogName 'Microsoft-Windows-WLAN-AutoConfig/Operational' -MaxEvents 20
# 8006 已完成启动承载网络 / 8008 开始停止承载网络
```

## 自定义

**换配色。** 把 `hotspot-icon.example.json` 复制成 `hotspot-icon.json`，改完重启托盘程序：

```json
{
  "On": "#22C55E",
  "Off": "#94A3B8",
  "Slash": "#EF4444",
  "Badge": "#0EA5E9",
  "Transition": "#F59E0B"
}
```

**整个换掉图标。** 把 `hotspot-on.png` / `hotspot-off.png`（或 `.ico`）放到脚本同目录，程序会优先用你的图片。

**重新生成文档里的预览图：**

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\HotspotTray.ps1 -PreviewIcons
```

## 常见问题

**手机搜不到热点。** 先用 `-Status` 确认 `State` 是不是 `Off`——如果是，热点根本没开。如果开着还是搜不到，通常是频段问题：上游 Wi-Fi 工作在 DFS 信道（5 GHz 的 52–144 信道）时，部分手机不会列出该信道上的热点。把热点固定到 2.4 GHz 能提高兼容性，代价是速率。

**报错提示「Hosted network supported: No」。** 这是预期情况，也正是本项目存在的原因——它不走那个接口。如果这个错误来自**别的**工具，那说明那个工具在你的硬件上没法用。

**托盘图标一直不出现。** 多半被收进溢出区（`^`）了。想固定：右键任务栏 → 任务栏设置 → 其他系统托盘图标 → 打开对应项。程序出错时会写进脚本同目录的 `hotspot-tray.log`。

**热点还是 5 分钟后掉了。** 说明有别的路径把超时重新打开了——最可能是你从系统设置面板而不是本工具开关的热点。本工具的两个入口每次开启时都会重新关一次超时。

## 卸载

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\install.ps1 -Uninstall
```

会删掉快捷方式，包括启动文件夹里那两个。代码文件保持不动。上面那个注册表值不会被动，想恢复系统默认行为就删掉它，或者在设置里把超时重新打开。

## 验证环境

在 Windows 11（内部版本 26200）配 Intel Wireless-AC 9560 的机器上做过完整验证，包括最关键的这条：**所有命令、托盘程序以及那个反射调用，在非管理员权限下都能正常工作**，所以双击桌面快捷方式就够了。

## 已知限制

- 单网卡同时当上行和热点时是分时复用，有客户端在跑时速率会下降
- 最多 8 个客户端，这是 Windows 的限制，不是本项目的
- 客户端的设备名不一定拿得到，有时只有 MAC 和主机名
- Windows 移动热点只做 NAT。客户端位于电脑后面的独立网段（`192.168.137.0/24`），不属于上游局域网

## 许可

[MIT](LICENSE)
