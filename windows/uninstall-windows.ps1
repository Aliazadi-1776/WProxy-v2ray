$ErrorActionPreference = 'Stop'
if ($env:OS -ne 'Windows_NT') { throw 'This uninstaller must be run on Windows.' }
$target = Join-Path $env:LOCALAPPDATA 'Programs\WProxy'
$shortcut = Join-Path ([Environment]::GetFolderPath('StartMenu')) 'Programs\WProxy.lnk'
if (Test-Path $shortcut) { Remove-Item $shortcut -Force }
if (Test-Path $target) { Remove-Item $target -Recurse -Force }
Write-Host 'WProxy program files were removed. Saved servers and subscriptions remain under %APPDATA%\WProxy.'
