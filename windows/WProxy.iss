#define MyAppName "WProxy"
#define MyAppPublisher "WProxy contributors"
#define MyAppURL "https://github.com/Aliazadi-1776/WProxy-v2ray"
#ifndef MyVersion
  #define MyVersion "2.5.0"
#endif
#ifndef MyBuildDir
  #define MyBuildDir "..\build\windows"
#endif

[Setup]
AppId={{B63C9FCB-D1C6-49A0-9C08-463E53762BD0}
AppName={#MyAppName}
AppVersion={#MyVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}/issues
AppUpdatesURL={#MyAppURL}/releases
DefaultDirName={localappdata}\Programs\WProxy
DefaultGroupName=WProxy
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
ArchitecturesAllowed=x64
ArchitecturesInstallIn64BitMode=x64
OutputDir=..\dist
OutputBaseFilename=WProxy-{#MyVersion}-Setup
SetupIconFile=..\icons\wproxy.ico
UninstallDisplayIcon={app}\icons\wproxy.ico
LicenseFile=..\LICENSE
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern
CloseApplications=no

[Tasks]
Name: "startup"; Description: "Start WProxy when I sign in"; GroupDescription: "Additional options:"; Flags: unchecked

[Files]
Source: "{#MyBuildDir}\wproxyctl.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#MyBuildDir}\xray\xray.exe"; DestDir: "{app}\bin"; Flags: ignoreversion
Source: "{#MyBuildDir}\xray\wintun.dll"; DestDir: "{app}\bin"; Flags: ignoreversion
Source: "{#MyBuildDir}\xray\geoip.dat"; DestDir: "{app}\bin"; Flags: ignoreversion
Source: "{#MyBuildDir}\xray\geosite.dat"; DestDir: "{app}\bin"; Flags: ignoreversion
Source: "{#MyBuildDir}\xray\LICENSE"; DestDir: "{app}\licenses"; DestName: "Xray-LICENSE"; Flags: ignoreversion
Source: "{#MyBuildDir}\xray\LICENSE-Wintun"; DestDir: "{app}\licenses"; Flags: ignoreversion
Source: "WProxy.ps1"; DestDir: "{app}\windows"; Flags: ignoreversion
Source: "..\icons\wproxy.ico"; DestDir: "{app}\icons"; Flags: ignoreversion
Source: "..\LICENSE"; DestDir: "{app}"; DestName: "LICENSE-WProxy"; Flags: ignoreversion

[Icons]
Name: "{group}\WProxy"; Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; Parameters: "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File ""{app}\windows\WProxy.ps1"" -Show"; WorkingDir: "{app}"; IconFilename: "{app}\icons\wproxy.ico"
Name: "{userstartup}\WProxy"; Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; Parameters: "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File ""{app}\windows\WProxy.ps1"""; WorkingDir: "{app}"; IconFilename: "{app}\icons\wproxy.ico"; Tasks: startup

[Run]
Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; Parameters: "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File ""{app}\windows\WProxy.ps1"" -Show"; WorkingDir: "{app}"; Description: "Launch WProxy"; Flags: nowait postinstall skipifsilent
