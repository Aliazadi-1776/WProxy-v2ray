param([switch]$Start)

$ErrorActionPreference = 'Stop'
if ($env:OS -ne 'Windows_NT') { throw 'This installer must be run on Windows 10 or Windows 11.' }
$sourceRoot = Split-Path -Parent $PSScriptRoot
$target = Join-Path $env:LOCALAPPDATA 'Programs\WProxy'
$python = Get-Command python.exe -ErrorAction SilentlyContinue
if (-not $python) { $python = Get-Command python -ErrorAction SilentlyContinue }
if (-not $python) { throw 'Install Python 3 for the current user, then run this script again.' }

$bundledXray = Join-Path $PSScriptRoot 'bin\xray.exe'
$pathXray = Get-Command xray.exe -ErrorAction SilentlyContinue
if (-not (Test-Path $bundledXray) -and -not $pathXray) {
    throw 'Download the official Xray Windows ZIP, extract its files into windows\bin, then run this installer again.'
}

New-Item -ItemType Directory -Force -Path (Join-Path $target 'cli'), (Join-Path $target 'windows'), (Join-Path $target 'icons') | Out-Null
Copy-Item (Join-Path $sourceRoot 'cli\wproxyctl.py') (Join-Path $target 'cli\wproxyctl.py') -Force
Copy-Item (Join-Path $PSScriptRoot 'WProxy.ps1') (Join-Path $target 'windows\WProxy.ps1') -Force
Copy-Item (Join-Path $sourceRoot 'icons\wproxy.ico') (Join-Path $target 'icons\wproxy.ico') -Force
if (Test-Path (Join-Path $PSScriptRoot 'bin')) {
    Copy-Item (Join-Path $PSScriptRoot 'bin') $target -Recurse -Force
}

$shortcutPath = Join-Path ([Environment]::GetFolderPath('StartMenu')) 'Programs\WProxy.lnk'
$shell = New-Object -ComObject WScript.Shell
$shortcut = $shell.CreateShortcut($shortcutPath)
$shortcut.TargetPath = (Get-Command powershell.exe).Source
$shortcut.Arguments = '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + (Join-Path $target 'windows\WProxy.ps1') + '" -Show'
$shortcut.WorkingDirectory = $target
$shortcut.IconLocation = (Join-Path $target 'icons\wproxy.ico')
$shortcut.Save()

& $python.Source (Join-Path $target 'cli\wproxyctl.py') --version
Write-Host "Installed WProxy 2.5.1 for the current Windows user: $target"
Write-Host 'Open WProxy from the Start menu. Windows will request administrator permission only when connecting or disconnecting the TUN.'
if ($Start) { Start-Process $shortcutPath }
