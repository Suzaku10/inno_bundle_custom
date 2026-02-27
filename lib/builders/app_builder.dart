import 'dart:io';

import 'package:inno_bundle/models/config.dart';
import 'package:inno_bundle/utils/constants.dart';
import 'package:path/path.dart' as p;
import 'package:inno_bundle/utils/cli_logger.dart';

/// A class responsible for building the app based on the provided configuration.
class AppBuilder {
  /// Configuration guiding the build process.
  final Config config;

  /// Creates an instance of [AppBuilder] with the given [config].
  AppBuilder(this.config);

  String _evaluateBuildArg(String arg) {
    if (!arg.contains('\$(')) return arg;

    final regExp = RegExp(r'\$\((.*?)\)');
    return arg.replaceAllMapped(regExp, (match) {
      final command = match.group(1);
      if (command == null || command.trim().isEmpty) return match.group(0)!;

      try {
        final result = Process.runSync(
          'cmd.exe',
          ['/c', command],
          runInShell: true,
        );
        if (result.exitCode == 0) {
          return (result.stdout as String).trim();
        } else {
          CliLogger.warning(
              "Failed to evaluate shell command '$command': \${result.stderr}");
          return match.group(0)!;
        }
      } catch (e) {
        CliLogger.warning("Error evaluating shell command '$command': $e");
        return match.group(0)!;
      }
    });
  }

  /// Builds the app using Flutter and returns the path to the build directory.
  ///
  /// If [config.app] is `false` and a valid build already exists, it skips the
  /// build process and returns the existing directory. Otherwise, it executes
  /// the Flutter build command and returns the newly generated build directory.
  Future<Directory> build() async {
    final buildDirPath = p.joinAll([
      Directory.current.path,
      ...appBuildDir,
      config.type.dirName,
    ]);
    final buildDir = Directory(buildDirPath);
    final versionParts = config.version.split("+");
    final buildName = versionParts[0];
    final buildNumber =
        versionParts.length == 1 ? "1" : versionParts.sublist(1).join("+");

    if (!config.app) {
      if (!buildDir.existsSync() || buildDir.listSync().isEmpty) {
        CliLogger.warning(
          "${config.type.dirName} build is not available, "
          "--no-app is ignored.",
        );
      } else {
        CliLogger.info("Skipping app...");
        return buildDir;
      }
    }

    final evaluatedArgsList = 
        config.buildArgsList.map(_evaluateBuildArg).toList();
    final evaluatedArgs = config.buildArgs != null 
        ? _evaluateBuildArg(config.buildArgs!) 
        : null;

    final process = await Process.start(
      "flutter",
      [
        'build',
        'windows',
        '--${config.type.name}',
        '--obfuscate',
        '--split-debug-info=build/obfuscate',
        '--build-name',
        buildName,
        '--build-number',
        buildNumber,
        ...evaluatedArgsList,
        if (evaluatedArgs != null) evaluatedArgs,
      ],
      runInShell: true,
      workingDirectory: Directory.current.path,
      mode: ProcessStartMode.inheritStdio,
    );

    final exitCode = await process.exitCode;

    if (exitCode != 0) exit(exitCode);
    return buildDir;
  }
}
