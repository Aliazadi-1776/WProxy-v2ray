# Windows 10/11 x64

WProxy 2.8.5 ships as a per-user `Setup.exe`. It includes the lightweight Tauri 2 desktop, a standalone WProxy controller, sing-box **1.14.4**, Xray **26.9.30**, Mihomo **1.19.33** and Wintun. End users do not install Python or download cores separately. Windows 10/11 supplies the WebView2 runtime used by Tauri.

The redesigned Manager uses the same dark-and-lime Tauri interface on Linux and Windows: a connection dial, traffic cards, a navigation rail and pages for servers, subscriptions, routing and settings. Server names containing emoji or non-Latin text are carried over UTF-8, and command failures appear inside the app. Visible windows refresh live status every 3.5 seconds; polling pauses while the window is hidden. Fonts and the WProxy SVG logo are bundled locally.

## Why it uses its own window instead of Win+A

Windows 11 has no public extension API for arbitrary third-party Quick Settings controls. Microsoft's native VPN integration uses a restricted VPN Provider capability and cannot host WProxy's custom subscription, server, ping and routing interface. WProxy therefore uses a normal Tauri window and does not patch Explorer.

References: [Microsoft answer about the missing Quick Settings extension API](https://learn.microsoft.com/en-gb/answers/questions/1124942/api-for-adding-an-item-in-the-windows-11-taskbar-p), [official VPN plug-in sample and restricted capability](https://github.com/microsoft/UwpVpnPluginSample), and [Windows VPN quick-setting behavior](https://support.microsoft.com/en-us/windows/experience/connectivity-networking/connect-to-a-vpn-in-windows).

## Install

1. Open the [WProxy v2.8.5 release](https://github.com/Aliazadi-1776/WProxy-v2ray/releases/tag/v2.8.5).
2. Download `WProxy-2.8.5-Setup.exe` and `WProxy-2.8.5-Setup.exe.sha256`.
3. In PowerShell, verify the download:

```powershell
Get-FileHash .\WProxy-2.8.5-Setup.exe -Algorithm SHA256
Get-Content .\WProxy-2.8.5-Setup.exe.sha256
```

The two hexadecimal hashes must match. Run Setup, optionally enable **Start WProxy when I sign in**, then leave **Launch WProxy** checked. Program files are installed under `%LOCALAPPDATA%\Programs\WProxy`; saved servers stay under `%APPDATA%\WProxy`. The current installer is not Authenticode-signed, so Windows SmartScreen may show an unknown-publisher warning; verify the release checksum before continuing.

The build workflow downloads the three official pinned core archives, verifies each SHA-256 before extraction, and packages their executables and upstream licenses. Xray's archive also supplies Wintun and geodata. Administrator approval is requested only for connect/disconnect because system TUN routes require elevation.

## Subscriptions and servers

- Use **Servers → Add server** to paste a share link, JSON/YAML, or import a file; use **Subscriptions** for a subscription URL.
- On **Dashboard**, press the dial / **Quick connect** for automatic selection from servers that pass the existing HTTPS check. On **Servers**, **Connect** selects a particular server and **Switch** replaces the active connection in one step. Press the connected Dashboard dial to disconnect, or open the active server's details.
- **Test latency** measures TCP responsiveness. Search, source/engine filters, latency/name sorting, favorites and list/grid views help manage longer lists. Open a server's details to test or remove it; disconnect an active server before deleting it.
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

Open **Routing** and choose one routing mode:

- **All traffic** — traffic uses the VPN;
- **Bypass selected** — listed sites/apps stay direct; the rest uses the VPN;
- **Only selected** — listed sites/apps use the VPN; everything else stays direct. Add at least one item before connecting.

For applications, choose **Choose application** to search running/installed applications, or **Browse executable** for an `.exe`. Selected items are saved as exact absolute paths. Reconnect after changing Windows routing. For example, to route only your browser, choose **Only selected** and add that browser; to keep a support application direct while the rest uses the VPN, use **Bypass selected** and add that application.

Site rules depend on protocol sniffing and may not identify traffic that only exposes an IP address or uses unsupported/encrypted name resolution. When a site rule is insufficient, select the browser/application itself. Process rules and site rules form a union. See [Xray routing matching](https://xtls.github.io/en/config/routing.html) and [WProxy routing details](ROUTING.md).

## Automatic updates

Open **Settings → Automatic updates** to enable updates. Enabling it triggers a check immediately; subsequent launches check again while it stays enabled. **Check now** provides a manual check. WProxy downloads the matching Setup executable and release `SHA256SUMS`, refuses a missing or mismatched hash, and launches Inno Setup. Reopen WProxy when installation completes. Updates use the same per-user installation directory and preserve the saved server store; the installer is currently not Authenticode-signed.

## Uninstall and private data

Use **Settings → Apps → Installed apps → WProxy → Uninstall**. The uninstaller removes program files and shortcuts but intentionally keeps `%APPDATA%\WProxy\store.json`. Remove that directory manually only if you also want to erase saved subscription URLs and proxy credentials. Disconnect WProxy before uninstalling.

## Verification status

GitHub Actions builds and launches the Windows Tauri/WebView2 executable, validates core schemas, verifies pinned official archives, compiles Inno Setup and publishes installer/release checksums. The current limit is native Windows TUN execution for sing-box and Mihomo; schema validation is not the same as a physical Windows connection.

A CI runner cannot prove behavior on every physical network. A final Windows 10 and Windows 11 test should still cover UAC, Wintun creation, DNS/IPv6, sleep/resume, network changes and YouTube playback with the user's own server. The runtime checks prevent a false `Connected` state when the adapter, route or HTTPS path is missing; they are not an anonymity or leak-proof guarantee.

## خلاصهٔ فارسی

برای ویندوز فقط `WProxy-2.8.5-Setup.exe` را از Release بگیر و هش آن را با فایل `.sha256` مقایسه کن؛ Python یا Core جدا لازم نیست. WProxy موتور سازگار را انتخاب می‌کند و فقط وقتی Connected نشان می‌دهد که آداپتور، Route و HTTPS تأیید شده باشند. رابط داخل Win+A نیست و در پنجرهٔ مستقل اجرا می‌شود.
