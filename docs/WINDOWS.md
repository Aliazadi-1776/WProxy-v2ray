# Windows 10/11 x64

WProxy 2.5.0 ships as a per-user `Setup.exe`. It includes a standalone WProxy command engine, the notification-area manager, and the official Xray **26.9.30** Windows x64 runtime with Wintun. End users do not install Python or download Xray separately.

## Why it is beside the clock, not inside Win+A

Windows 11 has no public extension API for arbitrary third-party Quick Settings controls. Microsoft's native VPN integration uses a restricted VPN Provider capability and cannot host WProxy's custom subscription, server, ping and routing interface. WProxy therefore uses the supported notification area and its own manager window; it does not patch Explorer.

References: [Microsoft answer about the missing Quick Settings extension API](https://learn.microsoft.com/en-gb/answers/questions/1124942/api-for-adding-an-item-in-the-windows-11-taskbar-p), [official VPN plug-in sample and restricted capability](https://github.com/microsoft/UwpVpnPluginSample), and [Windows VPN quick-setting behavior](https://support.microsoft.com/en-us/windows/experience/connectivity-networking/connect-to-a-vpn-in-windows).

## Install

1. Open the [WProxy v2.5.0 release](https://github.com/Aliazadi-1776/WProxy-v2ray/releases/tag/v2.5.0).
2. Download `WProxy-2.5.0-Setup.exe` and `WProxy-2.5.0-Setup.exe.sha256`.
3. In PowerShell, verify the download:

```powershell
Get-FileHash .\WProxy-2.5.0-Setup.exe -Algorithm SHA256
Get-Content .\WProxy-2.5.0-Setup.exe.sha256
```

The two hexadecimal hashes must match. Run Setup, optionally enable **Start WProxy when I sign in**, then leave **Launch WProxy** checked. Program files are installed under `%LOCALAPPDATA%\Programs\WProxy`; saved servers stay under `%APPDATA%\WProxy`. The current installer is not Authenticode-signed, so Windows SmartScreen may show an unknown-publisher warning; verify the release checksum before continuing.

The build workflow downloads `Xray-windows-64.zip` from the official XTLS v26.9.30 release, checks the pinned SHA-256 before extraction, and packages `xray.exe`, `wintun.dll`, geodata and their upstream licenses. Administrator approval is requested only for connect/disconnect because system TUN routes require elevation.

## Subscriptions and servers

- Use **Add** to paste a single share link or subscription URL.
- **Subscriptions** shows every subscription and its imported server count. Update or remove one subscription independently.
- **Nodes** shows each server's source subscription. Identical links from two subscriptions remain two source-owned entries; updating/removing one subscription cannot delete the other's entry.
- The provider's quota/expiry announcement links are filtered from connectable nodes.

## Connect and connection verification

Select a node and choose **Connect**. WProxy will not report `Connected` merely because `xray.exe` is running. It now requires all of the following:

1. bundled Xray 26.9.30 or newer and `wintun.dll` beside it;
2. Xray configuration validation;
3. a running WProxy Wintun adapter;
4. an IPv4 default route owned by that adapter;
5. a successful HTTPS request with explicit HTTP proxies disabled.

If any check fails, WProxy stops the partial tunnel and shows the reason. Runtime details are under `%LOCALAPPDATA%\WProxy\run`; `xray.json` contains proxy credentials and must not be shared. The TUN configuration uses a 1400 MTU, automatic IPv4/IPv6 routes, automatic outbound-interface selection, DNS servers and Xray's Windows Filtering Platform leak controls. See the [official Xray TUN reference](https://xtls.github.io/en/config/inbounds/tun.html).

## Application and site routing

Open **Routing** and choose one mode:

- **All traffic through VPN** — default;
- **Bypass listed sites/apps** — listed traffic is direct;
- **Only listed sites/apps use VPN** — everything else is direct.

For applications, choose **Choose apps…**. The picker lists running executables and can browse for any `.exe`; selected items are saved as exact absolute paths. Exact paths are more reliable than typing a process name. Xray process matching is case-sensitive; name-only selectors omit the `.exe` suffix. Reconnect after changing routing.

Site rules depend on protocol sniffing and may not identify traffic that only exposes an IP address or uses unsupported/encrypted name resolution. When a site rule is insufficient, select the browser/application itself. Process rules and site rules form a union. See [Xray routing matching](https://xtls.github.io/en/config/routing.html) and [WProxy routing details](ROUTING.md).

## Uninstall and private data

Use **Settings → Apps → Installed apps → WProxy → Uninstall**. The uninstaller removes program files and shortcuts but intentionally keeps `%APPDATA%\WProxy\store.json`. Remove that directory manually only if you also want to erase saved subscription URLs and proxy credentials. Disconnect WProxy before uninstalling.

## Verification status

GitHub Actions runs the shared parser/routing/subscription tests on Windows, builds the standalone executable, verifies the pinned official Xray archive, compiles the Inno Setup installer, runs `wproxyctl.exe --version`, and publishes a SHA-256 file. Linux tests additionally validate generated Xray rules and release contents.

A CI runner cannot prove behavior on every physical network. A final Windows 10 and Windows 11 test should still cover UAC, Wintun creation, DNS/IPv6, sleep/resume, network changes and YouTube playback with the user's own server. The runtime checks prevent a false `Connected` state when the adapter, route or HTTPS path is missing; they are not an anonymity or leak-proof guarantee.

## خلاصهٔ فارسی

برای ویندوز فقط `WProxy-2.5.0-Setup.exe` را از Release بگیر و هش آن را با فایل `.sha256` مقایسه کن؛ Python یا Xray جدا لازم نیست. تب **Subscriptions** تعداد سرورهای هر ساب را نشان می‌دهد و کانفیگ‌های دو ساب با هم قاطی نمی‌شوند. در **Routing → Choose apps…** برنامه‌های در حال اجرا یا فایل EXE را انتخاب کن. اتصال فقط وقتی Connected می‌شود که آداپتور، Route و HTTPS واقعاً تأیید شده باشند. به‌دلیل محدودیت ویندوز، رابط داخل Win+A نیست و کنار ساعت اجرا می‌شود.
