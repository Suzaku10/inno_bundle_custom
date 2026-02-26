void main() {
  String _run() {
    return '''
[Run]
Filename: "{app}\\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#StringChange('{#MyAppName}', '&', '&&')}}"; Flags: nowait postinstall skipifsilent
\n''';
  }
  print(_run());
}
