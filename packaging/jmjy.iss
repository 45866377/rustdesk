; 极简云远程 · Windows 单文件安装包（CI 内打包，Inno Setup 6）
#define MyAppName "极简云远程"
#define MyAppVer "1.5.1"

[Setup]
AppId={{7C4A8E52-9B1D-4A66-B3F0-1E2D5A7C9B04}}
AppName={#MyAppName}
AppVersion={#MyAppVer}
AppPublisher=极简云
DefaultDirName={autopf}\JmjyRemote
DefaultGroupName={#MyAppName}
UninstallDisplayName={#MyAppName}
UninstallDisplayIcon={app}\rustdesk.exe
OutputDir=..\packaging-out
OutputBaseFilename=JmjyRemote-1.5.1-x86_64
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
PrivilegesRequired=admin
ArchitecturesInstallIn64BitMode=x64compatible
CloseApplications=yes
RestartApplications=no

[Languages]
Name: "chs"; MessagesFile: "ChineseSimplified.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
Source: "..\rustdesk\*"; DestDir: "{app}"; Flags: recursesubdirs createallsubdirs ignoreversion

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\rustdesk.exe"
Name: "{group}\卸载 {#MyAppName}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\rustdesk.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\rustdesk.exe"; Description: "{cm:LaunchProgram,{#MyAppName}}"; Flags: nowait postinstall skipifsilent
