# Windows 10/11 frontend

WProxy 2.4.1 includes an experimental per-user notification-area application for Windows 10/11 x64. It shares the Python parser, private store, subscription reader and routing policy with Linux, but launches Xray's native Windows TUN directly instead of using NetworkManager.

## Why it is beside the clock, not inside Win+A

Windows 11 has no public extension API for arbitrary third-party Quick Settings controls. Microsoft's supported native VPN integration is a curated UWP VPN Provider capability; it can expose a VPN profile in Windows' VPN UI, but it is not a container for WProxy's custom subscription, server and ping interface. WProxy therefore uses the supported notification area and its own manager window.

References: [Microsoft answer about the missing Quick Settings extension API](https://learn.microsoft.com/en-gb/answers/questions/1124942/api-for-adding-an-item-in-the-windows-11-taskbar-p), [official VPN plug-in sample and restricted capability](https://github.com/microsoft/UwpVpnPluginSample), and [Windows VPN quick-setting behavior](https://support.microsoft.com/en-us/windows/experience/connectivity-networking/connect-to-a-vpn-in-windows).

## Install

1. Install 64-bit Python 3 for the current user and enable its PATH option.
2. Download an official Windows x64 Xray-core ZIP from [XTLS/Xray-core releases](https://github.com/XTLS/Xray-core/releases).
3. Extract the complete Xray archive, including companion files, into `windows\bin` in the WProxy source folder. Do not commit those binaries to the WProxy repository.
4. Open PowerShell in the WProxy folder and run:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\windows\install-windows.ps1 -Start
```

The installer copies WProxy to `%LOCALAPPDATA%\Programs\WProxy` and creates a Start-menu shortcut. It does not install a service, driver or global Python package. Connecting/disconnecting requests UAC because a system TUN and routes require administrator permission.

## Use and data

- Double-click the WProxy icon beside the clock to open Nodes, Add and Routing pages.
- Select a node and choose **Connect**. The active Xray PID is verified as `xray.exe` before WProxy stops it.
- Server/subscription data is stored under `%APPDATA%\WProxy\store.json`.
- Runtime configuration and logs are stored under `%LOCALAPPDATA%\WProxy\run`. The configuration contains proxy credentials; keep that directory private.
- The window may be closed while the tray app and tunnel continue. Use **Disconnect** before exiting when you want the tunnel stopped.

To uninstall program files while keeping saved servers/subscriptions:

```powershell
.\windows\uninstall-windows.ps1
```

## Verification status

The shared Python parser/routing generator has automated tests, including Windows TUN fields. The PowerShell files are syntax-parsed by Windows GitHub Actions. This release was built on Linux and has **not** completed a real Windows UAC, Wintun, route, DNS, sleep/resume or HTTPS-through-TUN test. Treat the Windows frontend as experimental until those checks pass on a Windows 10 and Windows 11 machine.

## خلاصهٔ فارسی

نسخهٔ ویندوز کنار ساعت اجرا می‌شود، چون Win+A اجازهٔ افزودن پنل دلخواه به برنامه‌های عادی نمی‌دهد. Python 3 و فایل رسمی Xray ویندوز لازم‌اند. اتصال و قطع به‌خاطر ساخت TUN پنجرهٔ UAC نشان می‌دهد. این نسخه هنوز روی ویندوز واقعی تست کامل نشده و نباید به‌عنوان نسخهٔ پایدار ویندوز معرفی شود.
