# Windows 10/11 x64

WProxy 2.8.0 ships as a per-user `Setup.exe`. It includes the lightweight Tauri 2 desktop, a standalone WProxy controller, sing-box **1.14.4**, Xray **26.9.30**, Mihomo **1.19.33** and Wintun. End users do not install Python or download cores separately. Windows 10/11 supplies the WebView2 runtime used by Tauri.

The manager uses one compact graphite-and-blue, DPI-aware shell on both Linux and Windows. It has a fixed navigation rail, persistent connection status and dedicated pages for servers, subscriptions, importing, split routing and settings. Server names containing emoji or non-Latin text are carried over UTF-8, and command failures are reported inside the app. There is no background status polling loop, so an idle window does not repeatedly start the command engine.

## Why it uses its own window instead of Win+A

Windows 11 has no public extension API for arbitrary third-party Quick Settings controls. Microsoft's native VPN integration uses a restricted VPN Provider capability and cannot host WProxy's custom subscription, server, ping and routing interface. WProxy therefore uses a normal Tauri window and does not patch Explorer.

References: [Microsoft answer about the missing Quick Settings extension API](https://learn.microsoft.com/en-gb/answers/questions/1124942/api-for-adding-an-item-in-the-windows-11-taskbar-p), [official VPN plug-in sample and restricted capability](https://github.com/microsoft/UwpVpnPluginSample), and [Windows VPN quick-setting behavior](https://support.microsoft.com/en-us/windows/experience/connectivity-networking/connect-to-a-vpn-in-windows).

## Install

1. Open the [WProxy v2.8.0 release](https://github.com/Aliazadi-1776/WProxy-v2ray/releases/tag/v2.8.0).
2. Download `WProxy-2.8.0-Setup.exe` and `WProxy-2.8.0-Setup.exe.sha256`.
3. In PowerShell, verify the download:

```powershell
Get-FileHash .\WProxy-2.8.0-Setup.exe -Algorithm SHA256
Get-Content .\WProxy-2.8.0-Setup.exe.sha256
```

The two hexadecimal hashes must match. Run Setup, optionally enable **Start WProxy when I sign in**, then leave **Launch WProxy** checked. Program files are installed under `%LOCALAPPDATA%\Programs\WProxy`; saved servers stay under `%APPDATA%\WProxy`. The current installer is not Authenticode-signed, so Windows SmartScreen may show an unknown-publisher warning; verify the release checksum before continuing.

The build workflow downloads the three official pinned core archives, verifies each SHA-256 before extraction, and packages their executables and upstream licenses. Xray's archive also supplies Wintun and geodata. Administrator approval is requested only for connect/disconnect because system TUN routes require elevation.

## Subscriptions and servers

- Use **Add connection** to paste a single share link; use **Subscriptions** for a subscription URL.
- On **Servers**, choose **Quick connect** to test all endpoints and connect to the lowest-latency responder, or use **Connect** on one row. **Test latency**, **Disconnect**, **Refresh** and **Remove** remain available.
- **Subscriptions** shows every subscription and its imported server count. Update or remove one subscription independently.
- Each server row shows its source subscription. Identical links from two subscriptions remain two source-owned entries; updating/removing one subscription cannot delete the other's entry.
- The provider's quota/expiry announcement links are filtered from connectable nodes.

## Connect and connection verification

Select a node and choose **Connect**. WProxy will not report `Connected` merely because a core process is running. It requires all of the following:

1. a compatible bundled core (and `wintun.dll` for Xray);
2. validation with the selected core;
3. a running WProxy Wintun adapter;
4. an IPv4 default route owned by that adapter;
5. a successful HTTPS request with explicit HTTP proxies disabled.

If any check fails, WProxy stops the partial tunnel and shows the reason. Runtime details are under `%LOCALAPPDATA%\WProxy\run`; generated config files contain proxy credentials and must not be shared. The selected adapter configures a 1400 MTU, routes, DNS and outbound-interface selection.

## Application and site routing

Open **Split routing** and choose one routing mode:

- **All traffic through VPN** — default;
- **Bypass listed sites/apps** — listed traffic is direct;
- **Only listed sites/apps use VPN** — everything else is direct.

For applications, choose **Choose application** and browse for an `.exe`; selected items are saved as exact absolute paths. Exact paths are more reliable than typing a process name. Reconnect after changing routing.

Site rules depend on protocol sniffing and may not identify traffic that only exposes an IP address or uses unsupported/encrypted name resolution. When a site rule is insufficient, select the browser/application itself. Process rules and site rules form a union. See [Xray routing matching](https://xtls.github.io/en/config/routing.html) and [WProxy routing details](ROUTING.md).

## Automatic updates

Enable **Automatic updates** in the sidebar to check GitHub releases when WProxy starts. WProxy downloads the matching Setup executable and the release `SHA256SUMS`, refuses a missing or mismatched hash, and then launches Inno Setup silently. Automatic update is opt-in and uses the same per-user installation directory; the installer itself is currently not Authenticode-signed.

## Uninstall and private data

Use **Settings → Apps → Installed apps → WProxy → Uninstall**. The uninstaller removes program files and shortcuts but intentionally keeps `%APPDATA%\WProxy\store.json`. Remove that directory manually only if you also want to erase saved subscription URLs and proxy credentials. Disconnect WProxy before uninstalling.

## Verification status

GitHub Actions builds and launches the Windows Tauri/WebView2 executable, validates core schemas, verifies pinned official archives, compiles Inno Setup and publishes installer/release checksums. The current limit is native Windows TUN execution for sing-box and Mihomo; schema validation is not the same as a physical Windows connection.

A CI runner cannot prove behavior on every physical network. A final Windows 10 and Windows 11 test should still cover UAC, Wintun creation, DNS/IPv6, sleep/resume, network changes and YouTube playback with the user's own server. The runtime checks prevent a false `Connected` state when the adapter, route or HTTPS path is missing; they are not an anonymity or leak-proof guarantee.

## خلاصهٔ فارسی

برای ویندوز فقط `WProxy-2.8.0-Setup.exe` را از Release بگیر و هش آن را با فایل `.sha256` مقایسه کن؛ Python یا Core جدا لازم نیست. WProxy موتور سازگار را انتخاب می‌کند و فقط وقتی Connected نشان می‌دهد که آداپتور، Route و HTTPS تأیید شده باشند. رابط داخل Win+A نیست و در پنجرهٔ مستقل اجرا می‌شود.
