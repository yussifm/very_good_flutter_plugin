import 'dart:io';
import 'package:path/path.dart' as path;

const _pluginDependencies = '''
  {{project_name.snakeCase()}}_android:
    path: ../{{project_name.snakeCase()}}_android
  {{project_name.snakeCase()}}_ios:
    path: ../{{project_name.snakeCase()}}_ios
  {{project_name.snakeCase()}}_linux:
    path: ../{{project_name.snakeCase()}}_linux
  {{project_name.snakeCase()}}_macos:
    path: ../{{project_name.snakeCase()}}_macos
  {{project_name.snakeCase()}}_platform_interface:
    path: ../{{project_name.snakeCase()}}_platform_interface
  {{project_name.snakeCase()}}_web:
    path: ../{{project_name.snakeCase()}}_web
  {{project_name.snakeCase()}}_windows:
    path: ../{{project_name.snakeCase()}}_windows''';

const _pluginPlatforms = '''
flutter:
  plugin:
    platforms:
      android:
        default_package: {{project_name.snakeCase()}}_android
      ios:
        default_package: {{project_name.snakeCase()}}_ios
      macos:
        default_package: {{project_name.snakeCase()}}_macos
      linux:
        default_package: {{project_name.snakeCase()}}_linux
      web:
        default_package: {{project_name.snakeCase()}}_web
      windows:
        default_package: {{project_name.snakeCase()}}_windows''';

final _staticPath = path.join('tool', 'generator', 'static');
final _githubPath = path.join('.github');
final _sourcePath = path.join('src');
final _targetPath = path.join('brick', '__brick__');
final _androidPath = path.join(_targetPath, 'my_plugin_android', 'android');
final _androidKotlinPath = path.join(_androidPath, 'src', 'main', 'kotlin');
final _sourceMyPluginKtPath = path.join(
  _androidKotlinPath,
  'com',
  'example',
  'my_plugin',
  'MyPluginPlugin.kt',
);
final _targetMyPluginKtPath = path.join(
  _androidKotlinPath,
  '{{org_name.pathCase()}}',
  '{{project_name.pascalCase()}}Plugin.kt',
);
final year = DateTime.now().year;
final copyrightHeader = '''
// Copyright (c) $year, Very Good Ventures
// https://verygood.ventures
//
// Use of this source code is governed by an MIT-style
// license that can be found in the LICENSE file or at
// https://opensource.org/licenses/MIT.
''';

const platforms = [
  'android',
  'ios',
  'linux',
  'macos',
  'web',
  'windows',
];

final excludedFiles = [
  path.join(
    _targetPath,
    '.github',
    'workflows',
    'generate_template.yaml',
  ),
  path.join(_targetPath, '.github', 'CODEOWNERS'),
];

void main() async {
  // Remove Previously Generated Files
  final targetDir = Directory(_targetPath);
  if (targetDir.existsSync()) {
    await targetDir.delete(recursive: true);
  }

  // Copy Project Files
  await Future.wait([
    Shell.cp(_sourcePath, _targetPath),
    Shell.cp(_githubPath, path.join(_targetPath)),
    Shell.cp('$_staticPath/', _targetPath),
    () async {
      await Shell.mkdir(File(_targetMyPluginKtPath).parent.path);
      await Shell.cp(_sourceMyPluginKtPath, _targetMyPluginKtPath);
      await Shell.rm(File(_sourceMyPluginKtPath).parent.parent.path);
    }()
  ]);

  // Remove excluded files
  await Future.wait(
    excludedFiles.map((file) => File(file).delete(recursive: true)),
  );

  // Add conditionals to platforms
  for (final platform in platforms) {
    final directoryPath = path.join(_targetPath, 'my_plugin_$platform');
    final conditionalPath = path.join(
      _targetPath,
      '{{#$platform}}my_plugin_$platform{{',
      '$platform}}',
    );

    Directory(conditionalPath).createSync(recursive: true);
    await Shell.cp('$directoryPath/', '$conditionalPath/');
    await Shell.rm(directoryPath);
  }

  await Future.wait(
    Directory(_targetPath)
        .listSync(recursive: true)
        .whereType<File>()
        .map((_) async {
      var file = _;
      if (!file.existsSync()) return;

      // Add copyright header to all .dart files
      if (path.extension(file.path) == '.dart') {
        final contents = await file.readAsString();
        file = await file.writeAsString('$copyrightHeader\n$contents');
      }

      // Template File Contents
      final contents =
          file.isAsset() ? await file.readAsBytes() : await file.readAsString();
      final templatedContents = (contents is String)
          ? contents
              .replaceAll('com.example.my_plugin', '{{org_name.dotCase()}}')
              .replaceAll('my_plugin', '{{project_name.snakeCase()}}')
              .replaceAll('my-plugin', '{{project_name.paramCase()}}')
              .replaceAll('MyPlugin', '{{project_name.pascalCase()}}')
              .replaceAll('myPlugin', '{{project_name.camelCase()}}')
              .replaceAll(
                'A very good Flutter federated plugin',
                '{{{description}}}',
              )
              .replaceAll(_pluginPlatforms, '{{> plugin_platforms.dart }}')
              .replaceAll(
                _pluginDependencies,
                '{{> plugin_dependencies.dart }}',
              )
          : contents;
      file = templatedContents is String
          ? await file.writeAsString(templatedContents)
          : await file.writeAsBytes(templatedContents as List<int>);

      /// Template file paths
      final fileSegments = file.path.split('/').sublist(2);
      if (fileSegments
          .any((e) => e.contains('my_plugin') || e.contains('MyPlugin'))) {
        final newSegments = fileSegments.map((e) {
          return e
              .replaceAll('MyPlugin', '{{project_name.pascalCase()}}')
              .replaceAll('my_plugin', '{{project_name.snakeCase()}}');
        });
        final newPathSegment = newSegments.join('/');
        final newPath = path.join(_targetPath, newPathSegment);
        final newFile = File(newPath)..createSync(recursive: true);
        templatedContents is String
            ? newFile.writeAsStringSync(templatedContents)
            : newFile.writeAsBytesSync(templatedContents as List<int>);
        file = newFile;
      }
    }),
  );

  // Clean up top-level directories
  const topLevelDirs = [
    'my_plugin',
    '{{#android}}my_plugin_android{{',
    '{{#ios}}my_plugin_ios{{',
    '{{#linux}}my_plugin_linux{{',
    '{{#macos}}my_plugin_macos{{',
    'my_plugin_platform_interface',
    '{{#web}}my_plugin_web{{',
    '{{#windows}}my_plugin_windows{{',
  ];
  for (final dir in topLevelDirs) {
    Directory(path.join(_targetPath, dir)).deleteSync(recursive: true);
  }
}

class Shell {
  static Future<void> cp(String source, String destination) {
    return _Cmd.run('cp', ['-rf', source, destination]);
  }

  static Future<void> rm(String source) {
    return _Cmd.run('rm', ['-rf', source]);
  }

  static Future<void> mkdir(String destination) {
    return _Cmd.run('mkdir', ['-p', destination]);
  }
}

class _Cmd {
  static Future<ProcessResult> run(
    String cmd,
    List<String> args, {
    bool throwOnError = true,
    String? processWorkingDir,
  }) async {
    final result = await Process.run(cmd, args,
        workingDirectory: processWorkingDir, runInShell: true);

    if (throwOnError) {
      _throwIfProcessFailed(result, cmd, args);
    }
    return result;
  }

  static void _throwIfProcessFailed(
    ProcessResult pr,
    String process,
    List<String> args,
  ) {
    if (pr.exitCode != 0) {
      final values = {
        'Standard out': pr.stdout.toString().trim(),
        'Standard error': pr.stderr.toString().trim()
      }..removeWhere((k, v) => v.isEmpty);

      String message;
      if (values.isEmpty) {
        message = 'Unknown error';
      } else if (values.length == 1) {
        message = values.values.single;
      } else {
        message = values.entries.map((e) => '${e.key}\n${e.value}').join('\n');
      }

      throw ProcessException(process, args, message, pr.exitCode);
    }
  }
}

extension on File {
  bool isAsset() {
    const extensions = {
      '.png',
      '.ico',
      '.svg',
      '.jpg',
      '.jpeg',
      '.mov',
      '.mp4',
      'mp3',
      '.wav',
      '.ttf'
    };
    final ext = path.extension(this.path);
    return extensions.contains(ext);
  }
}