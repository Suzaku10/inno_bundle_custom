import 'dart:io';

import 'package:inno_bundle/models/config.dart';
import 'package:inno_bundle/models/dll_entry.dart';
import 'package:inno_bundle/models/vcredist_mode.dart';
import 'package:inno_bundle/utils/cli_logger.dart';
import 'package:inno_bundle/utils/constants.dart';
import 'package:inno_bundle/utils/functions.dart';
import 'package:path/path.dart' as p;

/// A class responsible for generating the Inno Setup Script (ISS) file for the installer.
class ScriptBuilder {
  /// The configuration guiding the script generation process.
  final Config config;

  /// The directory containing the application files to be included in the installer.
  final Directory appDir;

  /// Creates a [ScriptBuilder] instance with the given [config] and [appDir].
  ScriptBuilder(this.config, this.appDir);

  String _setup() {
    final id = config.id;
    final name = config.name;
    final version = config.version;
    final publisher = config.publisher;
    final dirName = config.dirName;
    final outputBase = config.outputBaseFolder;
    final exeName = config.exeName;
    final privileges = config.admin ? 'admin' : 'lowest';
    var installerIcon = config.installerIcon;
    final arch = config.architecturesInstallIn64BitMode;
    final archStr = (arch != null && arch.isNotEmpty) 
        ? 'ArchitecturesInstallIn64BitMode=$arch\n' 
        : '';

    final disableDirPageStr = config.disableDirPage ? 'DisableDirPage=auto\n' : '';

    final outputDir = p.joinAll([
      Directory.current.path,
      ...installerBuildDir,
      config.type.dirName,
      config.outputFolderName,
    ]);

    // save default icon into temp directory to use its path.
    if (installerIcon == defaultInstallerIconPlaceholder) {
      final installerIconDirPath = p.joinAll([
        Directory.systemTemp.absolute.path,
        "${camelCase(name)}Installer",
      ]);
      installerIcon = persistDefaultInstallerIcon(installerIconDirPath);
    }

    return '''
#define Guid "$id"
#define MyAppName "$name"
#define MyAppVersion "$version"
#define MyAppPublisher "$publisher"
#define Dirname "$dirName"
#define OutputBase "$outputBase"
#define SetupIcon "$installerIcon"
#define MyAppExeName "$exeName"
#define Changelog "${config.changelogFile}"

[Setup]
; NOTE: The value of AppId uniquely identifies this application. Do not use the same AppId value in installers for other applications.
; (To generate a new GUID, click Tools | Generate GUID inside the IDE.)
AppId={#Guid}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
;AppVerName={#MyAppName} {#MyAppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={autopf}\\{#Dirname}
DisableProgramGroupPage=yes
; Uncomment the following line to run in non administrative install mode (install for current user only.)
;PrivilegesRequired=lowest
OutputBaseFilename={#OutputBase}
SetupIconFile={#SetupIcon}
${config.changelogFile.isNotEmpty ? 'InfoAfterFile={#Changelog}' : ''}
Compression=lzma
SolidCompression=yes
WizardStyle=modern
OutputDir=$outputDir
PrivilegesRequired=$privileges
$archStr
$disableDirPageStr
\n''';
  }

  String _languages() {
    String section = "[Languages]\n";
    for (final language in config.languages) {
      section += '${language.toInnoItem()}\n';
    }
    return '$section\n';
  }

  String _tasks() {
    return '''
[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}";
\n''';
  }

  String _files() {
    var section = "[Files]\n";

    // adding app build files
    final appFiles = appDir.listSync();

    for (final appFile in appFiles) {
      final filePath = appFile.absolute.path;
      if (FileSystemEntity.isDirectorySync(filePath)) {
        final fileName = p.basename(filePath);
        section += "Source: \"$filePath\\*\"; DestDir: \"{app}\\$fileName\"; "
            "Flags: ignoreversion recursesubdirs createallsubdirs\n";
      } else {
        // override the default exe file name from the name provided by
        // flutter build, to the inno_bundle.name property value (if provided)
        if (p.basename(filePath) == config.exePubspecName &&
            config.exeName != config.exePubspecName) {
          print("Renamed ${config.exePubspecName} ${config.exeName}");
          section += "Source: \"$filePath\"; DestDir: \"{app}\"; "
              "DestName: \"${config.exeName}\"; Flags: ignoreversion\n";
        } else {
          section += "Source: \"$filePath\"; DestDir: \"{app}\"; "
              "Flags: ignoreversion\n";
        }
      }
    }

    // adding optional DLL files from System32 (if they are available),
    // so that the end user is not required to install
    // MS Visual C++ redistributable to run the app.
    final dlls = config.dlls.toList();
    if (config.vcRedist == VcRedistMode.bundle) {
      dlls.addAll(DllEntry.vcEntries);
    }

    // copy all the dll files to the installer build directory
    final scriptDirPath = p.joinAll([
      Directory.systemTemp.absolute.path,
      "${camelCase(config.name)}Installer",
      config.type.dirName,
    ]);
    Directory(scriptDirPath).createSync(recursive: true);
    for (final dll in dlls) {
      final file = File(dll.absolutePath);
      if (!file.existsSync()) {
        // if the file is not required, skip it, otherwise exit with error.
        if (!dll.required) continue;
        CliLogger.exitError("Required DLL file \${file.path} does not exist.");
      }

      final dllPath = p.join(scriptDirPath, p.basename(file.path));
      final dllName = dll.name;
      file.copySync(dllPath);
      section += "Source: \"$dllPath\"; DestDir: \"{app}\"; "
          "DestName: \"$dllName\"; Flags: ignoreversion\n";
    }

    return '$section\n';
  }

  String _icons() {
    return '''
[Icons]
Name: "{autoprograms}\\{#MyAppName}"; Filename: "{app}\\{#MyAppExeName}"
Name: "{autodesktop}\\{#MyAppName}"; Filename: "{app}\\{#MyAppExeName}"; Tasks: desktopicon
\n''';
  }

  String _run() {
    return '''
[Run]
Filename: "{app}\\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#StringChange(MyAppName, '&', '&&')}}"; Flags: nowait postinstall skipifsilent
\n''';
  }

  String _downloadVcRedist() {
    if (config.vcRedist != VcRedistMode.download) return '';
    return '''
; This section will create a checkbox on the last page of the installer, checked it by default,
; if left checked after user click finish,
; the installer will open default browser and download the Visual C++ Redistributable
[Code]
var
  VCCheckBox: TCheckBox;

procedure InitializeWizard;
begin
  // Create a new checkbox below the default one on the last page
  VCCheckBox := TCheckBox.Create(WizardForm);
  VCCheckBox.Parent := WizardForm.FinishedPage;
  VCCheckBox.Caption := 'Download and install required Visual C++ runtime (recommended)';
  VCCheckBox.Checked := True; // Checked by default
  VCCheckBox.Left := WizardForm.RunList.Left; // Align with existing checkbox
  VCCheckBox.Top := WizardForm.RunList.Top + 25; // Place it below existing checkbox
  VCCheckBox.Width := WizardForm.RunList.Width;
end;

// This runs *after* the user clicks "Finish" on the last page
procedure CurStepChanged(CurStep: TSetupStep);
var
  ErrCode: Integer;
begin
  if (CurStep = ssDone) and VCCheckBox.Checked then
  begin
      ShellExec('', 'https://aka.ms/vs/17/release/vc_redist.x64.exe', '', '', SW_SHOWNORMAL, ewNoWait, ErrCode);
  end;
end;
\n''';
  }

  /// Generates the ISS script file and returns its path.
  Future<File> build() async {
    CliLogger.info("Generating ISS script...");
    final script = scriptHeader +
        _setup() +
        _languages() +
        _tasks() +
        _files() +
        _icons() +
        _run() +
        _downloadVcRedist();
    final relScriptPath = p.joinAll([
      ...installerBuildDir,
      config.type.dirName,
      "inno-script.iss",
    ]);
    final absScriptPath = p.join(Directory.current.path, relScriptPath);
    final scriptFile = File(absScriptPath);
    scriptFile.createSync(recursive: true);
    scriptFile.writeAsStringSync(script);
    CliLogger.success("Script generated $relScriptPath");
    return scriptFile;
  }
}
