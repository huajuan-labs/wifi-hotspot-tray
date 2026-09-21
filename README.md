# WiFi 热点托盘工具

把 Windows 内置的「移动热点」变成一个常驻右下角的小图标：右键开关、双击切换、状态实时显示，并顺手解决它**默认 5 分钟没人连就自动关闭**的问题。

不依赖 .NET SDK、Node.js 或任何第三方组件，只用系统自带的 Windows PowerShell 和 WinForms。

## 环境要求

- Windows 10 / 11
- **必须用 Windows PowerShell 5.1 运行**，也就是 `%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe`
- 不要在 PowerShell 7（`pwsh`）里跑。WinRT 异步投影依赖 `System.Runtime.WindowsRuntime`，PS7 上没有，调用会失败
- 网卡需要支持 Wi-Fi Direct（近十年的无线网卡基本都支持）

## 快速开始

```powershell
# 1. 创建桌面快捷方式并生成图标
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\install.ps1

# 2. 启动托盘程序
powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File .\HotspotTray.ps1
```

如果想让托盘图标开机自动出现、热点也自动打开：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\install.ps1 -WithAutoStart -WithAutoHotspot
```

## 文件说明

| 文件 | 作用 |
|---|---|
| `HotspotTray.ps1` | 托盘程序主体：图标绘制、右键菜单、状态轮询 |
| `hotspot.ps1` | 命令行版：`-On` / `-Off` / `-Status` / `-Watch` |
| `install.ps1` | 创建/删除快捷方式，生成图标 |
| `hotspot-icon.example.json` | 配色模板，复制成 `hotspot-icon.json` 后生效 |

`.ico`、`.log`、预览图都是运行后自动生成的，已经写进 `.gitignore`。

## 命令行用法

```powershell
# 查看状态（含已连接设备列表）
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\hotspot.ps1 -Status

# 开 / 关
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\hotspot.ps1 -On
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\hotspot.ps1 -Off

# 改网络名称和密码
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\hotspot.ps1 -On -Ssid MyAP -Passphrase "12345678"

# 开机场景：等到网络就绪再开，最多等 180 秒
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\hotspot.ps1 -On -WaitForNetwork

# 守护模式：被关掉就自动拉回来，Ctrl+C 退出
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\hotspot.ps1 -Watch

# 生成四种状态的图标预览图
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\HotspotTray.ps1 -PreviewIcons
```

## 托盘菜单

```
开启热点
关闭热点
────────────
状态：已开启（0/8 台设备）      ← 每 3 秒自动刷新
显示连接信息…                    ← 网络名称、密码、已连设备
────────────
开机自动启动                     ← 只把托盘图标放回右下角
开机自动开启热点                 ← 开机后连热点一起打开
────────────
退出
```

图标会随状态变化：

| 状态 | 图标 |
|---|---|
| 已关闭 | 灰色 Wi-Fi + 红色斜杠 |
| 已开启、无设备 | 绿色 |
| 已开启、有设备连接 | 绿色 + 蓝色圆点 |
| 切换中 | 橙色 |

## 实现上踩过的两个坑

这两点是这个项目存在的理由，也是大部分同类工具在你机器上跑不起来的原因。

### 1. 老式承载网络在新网卡上不可用

网上绝大多数「Windows 热点工具」走的是 `netsh wlan set hostednetwork` 那条老路（`WLAN_HOSTED_NETWORK_*` 系列 API）。Intel 从驱动里移除了这个能力，可以用下面这条命令确认：

```powershell
netsh wlan show drivers | Select-String 'Hosted network supported'
```

如果输出是 `No`，那些工具会直接失败。本项目改用现代的移动热点 API：

```powershell
[Windows.Networking.NetworkOperators.NetworkOperatorTetheringManager, Windows.Networking.NetworkOperators, ContentType = WindowsRuntime]::CreateFromConnectionProfile($profile)
```

### 2. 热点默认 5 分钟自动关闭

没有设备连接时，系统会把热点关掉，超时约 5 分钟。这件事在事件日志里看得很清楚：

```
netsh wlan show interfaces   # 看不到热点状态
Get-WinEvent -LogName 'Microsoft-Windows-WLAN-AutoConfig/Operational' -MaxEvents 20
# 8006 已完成启动承载网络 / 8008 开始停止承载网络
```

控制这个行为的开关叫 `NoConnectionsTimeout`，但它**不在默认接口上**，PowerShell 直接调用会报「不包含该方法」，必须走反射：

```powershell
$managerType = [Windows.Networking.NetworkOperators.NetworkOperatorTetheringManager, Windows.Networking.NetworkOperators, ContentType = WindowsRuntime]
$managerType.GetMethod('IsNoConnectionsTimeoutEnabled').Invoke($manager, @())
$managerType.GetMethod('DisableNoConnectionsTimeout').Invoke($manager, @())
```

关闭后会在注册表落地，重启依然有效：

```
HKLM\SYSTEM\CurrentControlSet\Services\icssvc\Settings\PeerlessTimeoutEnabled = 0
```

## 自定义

**换配色**：把 `hotspot-icon.example.json` 复制成 `hotspot-icon.json`，改颜色值，重启托盘程序。

```json
{
  "On": "#22C55E",
  "Off": "#94A3B8",
  "Slash": "#EF4444",
  "Badge": "#0EA5E9",
  "Transition": "#F59E0B"
}
```

**整个换掉图标**：往这个目录放 `hotspot-on.png` 和 `hotspot-off.png`（`.ico` 也行），程序会优先用你的图片。

## 常见问题

**手机搜不到热点？** 先确认热点还在开着（`-Status` 看 `State`）。若确实开着仍搜不到，多半是频段问题：如果上游 Wi-Fi 工作在 DFS 信道（例如 5 GHz 的 52/100 信道），部分手机扫描时不会列出该信道上的热点。这种情况把热点频段固定到 2.4 GHz 兼容性更好。

**能管理已连接设备吗？** 能看不能踢。`GetTetheringClients()` 只提供查询，API 里没有断开某个客户端的接口。要踢设备只能改密码让全部设备重连，或者关掉热点再开。

**日志在哪？** 同目录的 `hotspot-tray.log`，只记录启动、开关和错误。

## 卸载

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\install.ps1 -Uninstall
```

会把快捷方式删干净，代码文件不动。注意托盘菜单里的「开机自动启动」会在启动文件夹里额外放一个快捷方式，`-Uninstall` 也会一并清掉。

## 已知限制

- 单网卡同时当热点和连接上游时是分时复用，速率会受影响
- 最多 8 个客户端，这是 Windows 的固定上限
- 客户端的设备名不一定能拿到，有时只有 MAC 和主机名

## 许可

[MIT](LICENSE)
