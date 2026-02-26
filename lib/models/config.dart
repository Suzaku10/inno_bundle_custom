import 'dart:io';
import 'package:inno_bundle/models/build_type.dart';
import 'package:inno_bundle/models/language.dart';
import 'package:inno_bundle/models/dll_entry.dart';
import 'package:inno_bundle/models/vcredist_mode.dart';
import 'package:inno_bundle/utils/cli_logger.dart';
import 'package:inno_bundle/utils/constants.dart';
import 'package:inno_bundle/utils/functions.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';
import 'package:yaml/yaml.dart';

/// A class representing the configuration for building a Windows installer using Inno Setup.
class Config {
  /// The unique identifier (UUID) for the app being packaged.
  final String id;

  /// The global pubspec name attribute, same name of the exe generated from flutter build.
  final String pubspecName;

  /// The name of the app after packaging.
  final String name;

  /// A description of the app being packaged.
  final String description;

  /// The app's version.
  final String version;

  /// The name of the publisher or maintainer.
  final String publisher;

  /// The app's homepage URL.
  final String url;

  /// The URL for support resources.
  final String supportUrl;

  /// The URL for checking for updates.
  final String updatesUrl;

  /// The path to the installer icon file.
  final String installerIcon;

  // The path to the text license file.
  final String licenseFile;

  // The path to the text changelog file.
  final String changelogFile;

  /// The default installer directory name.
  final String dirName;

  /// The output base folder.
  final String outputBaseFolder;

  /// The custom executable name.
  final String exeName;

  /// The mode for handling the Visual C++ Redistributable.
  final VcRedistMode vcRedist;

  /// List of dlls to be included in the installer.
  final List<DllEntry> dlls;

  /// Custom list of arguments for `flutter build windows`.
  final List<String> buildArgsList;

  /// The supported languages for the installer.
  final List<Language> languages;

  /// Whether the installer requires administrator privileges.
  final bool admin;

  /// The build type (debug or release).
  final BuildType type;

  /// Whether to include the app in the installer.
  final bool app;

  /// Whether to create an installer file.
  final bool installer;

  /// Whether to disable the directory selection page.
  final bool disableDirPage;

  /// Arguments to be passed to flutter build.
  final String? buildArgs;

  /// The flavor to build (e.g. dev, staging, prod).
  final String? flavor;

  /// The value for ArchitecturesInstallIn64BitMode in the Inno Setup script.
  /// If null or empty, the line will be omitted from the script (defaults to x86).
  final String? architecturesInstallIn64BitMode;

  /// Creates a [Config] instance with default values.
  const Config({
    required this.buildArgs,
    required this.flavor,
    required this.architecturesInstallIn64BitMode,
    required this.id,
    required this.pubspecName,
    required this.name,
    required this.description,
    required this.version,
    required this.publisher,
    required this.url,
    required this.supportUrl,
    required this.updatesUrl,
    required this.installerIcon,
    required this.languages,
    required this.admin,
    required this.licenseFile,
    required this.changelogFile,
    required this.dirName,
    required this.outputBaseFolder,
    required this.exeName,
    required this.vcRedist,
    required this.dlls,
    required this.buildArgsList,
    this.type = BuildType.debug,
    this.app = true,
    this.installer = true,
    this.disableDirPage = true,
  });

  /// The name of the executable file that is created with flutter build.
  String get exePubspecName => "$pubspecName.exe";

  /// The dynamic folder name for the installer output.
  String get outputFolderName {
    final flavorSuffix = (flavor != null && flavor!.isNotEmpty) ? "-$flavor" : "";
    return "$name$flavorSuffix-$version";
  }

  /// Creates a [Config] instance from a JSON map, typically read from `pubspec.yaml`.
  ///
  /// Validates the configuration and exits with an error if invalid values are found.
  factory Config.fromJson(
    Map<String, dynamic> json, {
    BuildType type = BuildType.debug,
    bool app = true,
    bool installer = true,
    required String? buildArgs,
    required String? appVersion,
    String? buildName,
    String? buildNumber,
    required String? flavor,
  }) {
    final blockName = flavor != null && flavor.isNotEmpty 
        ? 'inno_bundle_$flavor' 
        : 'inno_bundle';

    if (json[blockName] is! Map<String, dynamic>) {
      if (flavor != null && flavor.isNotEmpty) {
        CliLogger.exitError("$blockName section is missing from pubspec.yaml.");
      } else {
        CliLogger.exitError("inno_bundle section is missing from pubspec.yaml.");
      }
    }
    final Map<String, dynamic> inno = json[blockName];

    if (inno['id'] is! String) {
      CliLogger.exitError(
          "$blockName.id attribute is missing from pubspec.yaml. "
          "Run `dart run inno_bundle:guid` to generate a new one, "
          "then put it in your pubspec.yaml.");
    } else if (!Uuid.isValidUUID(fromString: inno['id'])) {
      CliLogger.exitError("$blockName.id from pubspec.yaml is not valid. "
          "Run `dart run inno_bundle:guid` to generate a new one, "
          "then put it in your pubspec.yaml.");
    }
    final String id = inno['id'];

    if (json['name'] is! String) {
      CliLogger.exitError("name attribute is missing from pubspec.yaml.");
    }
    final String pubspecName = json['name'];

    if (inno['name'] != null && !validFilenameRegex.hasMatch(inno['name'])) {
      CliLogger.exitError("$blockName.name from pubspec.yaml is not valid. "
          "`${inno['name']}` is not a valid file name.");
    }
    final String name = inno['name'] ?? pubspecName;

    String? resolvedVersion = appVersion;
    if (buildName != null || buildNumber != null) {
      final pubspecVersion = (inno['version'] ?? json['version'])?.toString();
      final defaultName = pubspecVersion?.split('+').first ?? '1.0.0';
      final defaultNumber = pubspecVersion?.contains('+') == true 
          ? pubspecVersion!.split('+').sublist(1).join('+') 
          : '1';
      final finalName = buildName ?? defaultName;
      final finalNumber = buildNumber ?? defaultNumber;
      resolvedVersion = '$finalName+$finalNumber';
    }

    if ((resolvedVersion ?? inno['version'] ?? json['version']) is! String) {
      CliLogger.exitError("version attribute is missing from pubspec.yaml.");
    }
    final String version = resolvedVersion ?? inno['version'] ?? json['version'];

    if ((inno['description'] ?? json['description']) is! String) {
      CliLogger.exitError(
          "description attribute is missing from pubspec.yaml.");
    }
    final String description = inno['description'] ?? json['description'];

    if ((inno['publisher'] ?? json['maintainer']) is! String) {
      CliLogger.exitError("maintainer or $blockName.publisher attributes are "
          "missing from pubspec.yaml.");
    }
    final String publisher = inno['publisher'] ?? json['maintainer'];

    final url = (inno['url'] ?? json['homepage'] ?? "") as String;
    final supportUrl = (inno['support_url'] as String?) ?? url;
    final updatesUrl = (inno['updates_url'] as String?) ?? url;

    if (inno['installer_icon'] != null && inno['installer_icon'] is! String) {
      CliLogger.exitError("$blockName.installer_icon attribute is invalid "
          "in pubspec.yaml.");
    }
    final installerIcon = inno['installer_icon'] != null
        ? p.join(
            Directory.current.path,
            p.fromUri(inno['installer_icon']),
          )
        : defaultInstallerIconPlaceholder;
    if (installerIcon != defaultInstallerIconPlaceholder &&
        !File(installerIcon).existsSync()) {
      CliLogger.exitError(
          "$blockName.installer_icon attribute value is invalid, "
          "`$installerIcon` file does not exist.");
    }

    if (inno['languages'] != null && inno['languages'] is! List<String>) {
      CliLogger.exitError("$blockName.languages attribute is invalid "
          "in pubspec.yaml, only a list of strings is allowed.");
    }
    final languages = (inno['languages'] as List<String>?)?.map((l) {
          final language = Language.getByNameOrNull(l);
          if (language == null) {
            CliLogger.exitError("problem in $blockName.languages attribute "
                "in pubspec.yaml, language `$l` is not supported.");
          }
          return language!;
        }).toList(growable: false) ??
        Language.values;

    if (inno['admin'] != null && inno['admin'] is! bool) {
      CliLogger.exitError(
          "$blockName.admin attribute is invalid boolean value "
          "in pubspec.yaml");
    }
    final bool admin = inno['admin'] ?? true;

    if (inno['license_file'] != null && inno['license_file'] is! String) {
      CliLogger.exitError("$blockName.license_file attribute is invalid "
          "in pubspec.yaml.");
    }

    final licenseFilePath = p.join(
      Directory.current.path,
      inno['license_file'] != null
          ? p.fromUri(inno['license_file'])
          : 'LICENSE',
    );
    final licenseFile =
        File(licenseFilePath).existsSync() ? licenseFilePath : '';

    if (inno['changelog'] != null && inno['changelog'] is! String) {
      CliLogger.exitError("$blockName.changelog attribute is invalid "
          "in pubspec.yaml.");
    }

    final changelogFilePath = p.join(
      Directory.current.path,
      inno['changelog'] != null
          ? p.fromUri(inno['changelog'])
          : 'CHANGELOG.md',
    );
    final changelogFile =
        File(changelogFilePath).existsSync() ? changelogFilePath : '';

    final String dirName = inno['dirname'] ?? name;
    
    // allow installer_name with outputbaseFolder as fallback
    final String outputBaseFolder = inno['installer_name'] ?? inno['outputbaseFolder'] ?? '${camelCase(name)}-x86_64-$version-Installer';
    
    final String exeName = inno['exename'] ?? "$name.exe";

    if (inno['vc_redist'] != null &&
        inno['vc_redist'] is! bool &&
        inno['vc_redist'] != "download") {
      CliLogger.exitError("$blockName.vc_redist attribute is invalid value "
          "in pubspec.yaml");
    }
    final vcRedist = VcRedistMode.fromOption(inno['vc_redist'] ?? true);

    if (inno['dlls'] != null && inno['dlls'] is! List) {
      CliLogger.exitError("$blockName.dlls attribute is invalid "
          "in pubspec.yaml, only a list of dll entries is allowed.");
    }
    final dlls = ((inno['dlls'] ?? []) as List)
        .map((d) {
          if (d == null) return null;

          final dllError = DllEntry.validateConfig(d);
          if (dllError != null) CliLogger.exitError(dllError);

          return DllEntry.fromJson(d);
        })
        .whereType<DllEntry>()
        .toList(growable: false);

    if (inno['build_args'] != null && inno['build_args'] is! List) {
      CliLogger.exitError("$blockName.build_args attribute is invalid "
          "in pubspec.yaml, only a list of strings is allowed.");
    }
    final buildArgsList = ((inno['build_args'] ?? []) as List)
        .map((e) => e.toString())
        .toList(growable: false);

    final rawArch = inno['architectures_install_in_64_bit_mode'];
    String? architecturesInstallIn64BitMode;
    if (rawArch is bool) {
      architecturesInstallIn64BitMode = rawArch ? 'x64' : null;
    } else if (rawArch != null) {
      final archStr = rawArch.toString();
      architecturesInstallIn64BitMode = archStr == 'x86' ? null : archStr;
    } else {
      architecturesInstallIn64BitMode = null;
    }

    if (inno['disable_dir_page'] != null && inno['disable_dir_page'] is! bool) {
      CliLogger.exitError(
          "$blockName.disable_dir_page attribute is invalid boolean value "
          "in pubspec.yaml");
    }
    final bool disableDirPage = inno['disable_dir_page'] ?? true;

    return Config(
      buildArgs: buildArgs,
      id: id,
      pubspecName: pubspecName,
      name: name,
      description: description,
      version: version,
      publisher: publisher,
      url: url,
      supportUrl: supportUrl,
      updatesUrl: updatesUrl,
      installerIcon: installerIcon,
      languages: languages,
      admin: admin,
      type: type,
      app: app,
      installer: installer,
      licenseFile: licenseFile,
      changelogFile: changelogFile,
      dirName: dirName,
      outputBaseFolder: outputBaseFolder,
      exeName: exeName,
      vcRedist: vcRedist,
      dlls: dlls,
      buildArgsList: buildArgsList,
      flavor: flavor,
      architecturesInstallIn64BitMode: architecturesInstallIn64BitMode,
      disableDirPage: disableDirPage,
    );
  }

  /// Creates a [Config] instance directly from the `pubspec.yaml` file.
  ///
  /// Provides a convenient way to load configuration without manual JSON parsing.
  factory Config.fromFile({
    BuildType type = BuildType.debug,
    bool app = true,
    bool installer = true,
    required String? buildArgs,
    required String? appVersion,
    String? buildName,
    String? buildNumber,
    String? flavor,
  }) {
    const filePath = 'pubspec.yaml';
    final yamlMap = loadYaml(File(filePath).readAsStringSync()) as Map;
    // yamlMap has the type YamlMap, which has several unwanted side effects
    final yamlConfig = yamlToMap(yamlMap as YamlMap);
    return Config.fromJson(
      yamlConfig,
      type: type,
      app: app,
      installer: installer,
      buildArgs: buildArgs,
      appVersion: appVersion,
      buildName: buildName,
      buildNumber: buildNumber,
      flavor: flavor,
    );
  }

  /// Returns a string containing the config attributes as environment variables.
  String toEnvironmentVariables() {
    final variables = <String, String>{
      'APP_ID': id,
      'PUBSPEC_NAME': pubspecName,
      'APP_NAME': name,
      'APP_NAME_CAMEL_CASE': camelCase(name),
      'APP_DESCRIPTION': description,
      'APP_VERSION': version,
      'APP_PUBLISHER': publisher,
      'APP_URL': url,
      'APP_SUPPORT_URL': supportUrl,
      'APP_UPDATES_URL': updatesUrl,
      'APP_INSTALLER_ICON': installerIcon,
      'APP_LANGUAGES': languages.map((l) => l.name).join(','),
      'APP_ADMIN': admin.toString(),
      'APP_TYPE': type.name,
      'APP_BUILD_APP': app.toString(),
      'APP_BUILD_INSTALLER': installer.toString(),
    };

    return variables.entries
        .map((entry) => '${entry.key}=${entry.value}')
        .join('\n');
  }
}
