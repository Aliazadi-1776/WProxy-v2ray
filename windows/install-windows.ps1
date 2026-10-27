param([switch]$Start)

$ErrorActionPreference = 'Stop'
if ($env:OS -ne 'Windows_NT') { throw 'This installer must be run on Windows 10 or Windows 11.' }
$sourceRoot = Split-Path -Parent $PSScriptRoot
$target = Join-Path $env:LOCALAPPDATA 'Programs\WProxy'
$desktopCandidates = @(
    (Join-Path $sourceRoot 'build\windows\WProxy.exe'),
    (Join-Path $sourceRoot 'desktop\src-tauri\target\release\wproxy-desktop.exe')
)
$desktop = $desktopCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $desktop) { throw 'Build the Tauri desktop first with: cd desktop; npm ci; npm run build; cargo build --release --manifest-path src-tauri/Cargo.toml' }
$python = Get-Command python.exe -ErrorAction SilentlyContinue
if (-not $python) { $python = Get-Command python -ErrorAction SilentlyContinue }
if (-not $python) { throw 'Install Python 3 for the current user, then run this script again.' }

$bundledXray = Join-Path $PSScriptRoot 'bin\xray.exe'
$pathXray = Get-Command xray.exe -ErrorAction SilentlyContinue
if (-not (Test-Path $bundledXray) -and -not $pathXray) {
    throw 'Download the official Xray Windows ZIP, extract its files into windows\bin, then run this installer again.'
}

New-Item -ItemType Directory -Force -Path (Join-Path $target 'cli'), (Join-Path $target 'icons') | Out-Null
Copy-Item (Join-Path $sourceRoot 'cli\wproxyctl.py') (Join-Path $target 'cli\wproxyctl.py') -Force
Copy-Item $desktop (Join-Path $target 'WProxy.exe') -Force
Copy-Item (Join-Path $sourceRoot 'icons\wproxy.ico') (Join-Path $target 'icons\wproxy.ico') -Force
if (Test-Path (Join-Path $PSScriptRoot 'bin')) {
    Copy-Item (Join-Path $PSScriptRoot 'bin') $target -Recurse -Force
}

$shortcutPath = Join-Path ([Environment]::GetFolderPath('StartMenu')) 'Programs\WProxy.lnk'
$shell = New-Object -ComObject WScript.Shell
$shortcut = $shell.CreateShortcut($shortcutPath)
$shortcut.TargetPath = (Join-Path $target 'WProxy.exe')
$shortcut.Arguments = ''
$shortcut.WorkingDirectory = $target
$shortcut.IconLocation = (Join-Path $target 'icons\wproxy.ico')
$shortcut.Save()

& $python.Source (Join-Path $target 'cli\wproxyctl.py') --version
Write-Host "Installed WProxy 2.7.3 for the current Windows user: $target"
Write-Host 'Open WProxy from the Start menu. Windows will request administrator permission only when connecting or disconnecting the TUN.'
if ($Start) { Start-Process $shortcutPath }
