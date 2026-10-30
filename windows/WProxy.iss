#define MyAppName "WProxy"
#define MyAppPublisher "WProxy contributors"
#define MyAppURL "https://github.com/Aliazadi-1776/WProxy-v2ray"
#ifndef MyVersion
  #define MyVersion "2.7.8"
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
ArchitecturesAllowed=x64os
ArchitecturesInstallIn64BitMode=x64os
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
Source: "{#MyBuildDir}\WProxy.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#MyBuildDir}\wproxyctl.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#MyBuildDir}\xray\xray.exe"; DestDir: "{app}\bin"; Flags: ignoreversion
Source: "{#MyBuildDir}\xray\wintun.dll"; DestDir: "{app}\bin"; Flags: ignoreversion
Source: "{#MyBuildDir}\xray\geoip.dat"; DestDir: "{app}\bin"; Flags: ignoreversion
Source: "{#MyBuildDir}\xray\geosite.dat"; DestDir: "{app}\bin"; Flags: ignoreversion
Source: "{#MyBuildDir}\xray\LICENSE"; DestDir: "{app}\licenses"; DestName: "Xray-LICENSE"; Flags: ignoreversion
Source: "{#MyBuildDir}\xray\LICENSE-Wintun"; DestDir: "{app}\licenses"; Flags: ignoreversion
Source: "..\icons\wproxy.ico"; DestDir: "{app}\icons"; Flags: ignoreversion
Source: "..\LICENSE"; DestDir: "{app}"; DestName: "LICENSE-WProxy"; Flags: ignoreversion
Source: "..\THIRD_PARTY_NOTICES.md"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{group}\WProxy"; Filename: "{app}\WProxy.exe"; WorkingDir: "{app}"; IconFilename: "{app}\icons\wproxy.ico"
Name: "{userstartup}\WProxy"; Filename: "{app}\WProxy.exe"; WorkingDir: "{app}"; IconFilename: "{app}\icons\wproxy.ico"; Tasks: startup

[Run]
Filename: "{app}\WProxy.exe"; WorkingDir: "{app}"; Description: "Launch WProxy"; Flags: nowait postinstall skipifsilent
