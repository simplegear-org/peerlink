import 'dart:io';

final _pubspecVersionPattern = RegExp(
  r'^version:\s*([0-9]+)\.([0-9]+)\.([0-9]+)\+([0-9]+)\s*$',
);
final _rawVersionPattern = RegExp(r'^([0-9]+)\.([0-9]+)\.([0-9]+)\+([0-9]+)$');

void main(List<String> args) {
  if (args.isEmpty) {
    _printUsageAndExit();
  }

  final pubspec = File('pubspec.yaml');
  if (!pubspec.existsSync()) {
    stderr.writeln('pubspec.yaml not found');
    exit(1);
  }

  final lines = pubspec.readAsLinesSync();
  final versionIndex = lines.indexWhere(
    (line) => line.trimLeft().startsWith('version:'),
  );
  if (versionIndex == -1) {
    stderr.writeln('version line not found in pubspec.yaml');
    exit(1);
  }

  final match = _pubspecVersionPattern.firstMatch(lines[versionIndex].trim());
  if (match == null) {
    stderr.writeln('unsupported version format; expected x.y.z+n');
    exit(1);
  }

  final current = _Version(
    major: int.parse(match.group(1)!),
    minor: int.parse(match.group(2)!),
    patch: int.parse(match.group(3)!),
    build: int.parse(match.group(4)!),
  );

  final next = _nextVersion(current, args);
  _writeLines(pubspec, lines..[versionIndex] = 'version: ${next.value}');
  _syncPlatformVersions(next);
  stdout.writeln(next.value);
}

void _syncPlatformVersions(_Version version) {
  _updateKeyValueFile(File('android/local.properties'), <String, String>{
    'flutter.versionName': version.name,
    'flutter.versionCode': version.build.toString(),
  });
  _updateKeyValueFile(File('ios/Flutter/Generated.xcconfig'), <String, String>{
    'FLUTTER_BUILD_NAME': version.name,
    'FLUTTER_BUILD_NUMBER': version.build.toString(),
  });
  _updateKeyValueFile(
    File('macos/Flutter/ephemeral/Flutter-Generated.xcconfig'),
    <String, String>{
      'FLUTTER_BUILD_NAME': version.name,
      'FLUTTER_BUILD_NUMBER': version.build.toString(),
    },
  );
  _updateApplePlistVersion(File('ios/Flutter/AppFrameworkInfo.plist'), version);
  _updateXcodeProjectVersion(
    File('macos/Runner.xcodeproj/project.pbxproj'),
    version,
  );
}

void _updateKeyValueFile(File file, Map<String, String> values) {
  if (!file.existsSync()) {
    return;
  }
  final lines = file.readAsLinesSync();
  var changed = false;
  for (var i = 0; i < lines.length; i += 1) {
    for (final entry in values.entries) {
      if (lines[i].startsWith('${entry.key}=')) {
        final nextLine = '${entry.key}=${entry.value}';
        if (lines[i] != nextLine) {
          lines[i] = nextLine;
          changed = true;
        }
      }
    }
  }
  if (changed) {
    _writeLines(file, lines);
  }
}

void _updateApplePlistVersion(File file, _Version version) {
  if (!file.existsSync()) {
    return;
  }
  var content = file.readAsStringSync();
  content = _replacePlistStringValue(
    content,
    key: 'CFBundleShortVersionString',
    value: version.name,
  );
  content = _replacePlistStringValue(
    content,
    key: 'CFBundleVersion',
    value: version.build.toString(),
  );
  file.writeAsStringSync(_withTrailingNewline(content));
}

String _replacePlistStringValue(
  String content, {
  required String key,
  required String value,
}) {
  final pattern = RegExp(
    '(<key>${RegExp.escape(key)}</key>\\s*<string>)([^<]*)(</string>)',
    multiLine: true,
  );
  return content.replaceFirstMapped(
    pattern,
    (match) => '${match.group(1)}$value${match.group(3)}',
  );
}

void _updateXcodeProjectVersion(File file, _Version version) {
  if (!file.existsSync()) {
    return;
  }
  var content = file.readAsStringSync();
  content = content.replaceAllMapped(
    RegExp(r'CURRENT_PROJECT_VERSION = [^;]+;'),
    (_) => 'CURRENT_PROJECT_VERSION = ${version.build};',
  );
  content = content.replaceAllMapped(
    RegExp(r'MARKETING_VERSION = [^;]+;'),
    (_) => 'MARKETING_VERSION = ${version.name};',
  );
  file.writeAsStringSync(_withTrailingNewline(content));
}

void _writeLines(File file, List<String> lines) {
  file.writeAsStringSync('${lines.join('\n')}\n');
}

String _withTrailingNewline(String value) {
  return value.endsWith('\n') ? value : '$value\n';
}

_Version _nextVersion(_Version current, List<String> args) {
  switch (args.first) {
    case 'patch':
      return _Version(
        major: current.major,
        minor: current.minor,
        patch: current.patch + 1,
        build: current.build + 1,
      );
    case 'minor':
      return _Version(
        major: current.major,
        minor: current.minor + 1,
        patch: 0,
        build: current.build + 1,
      );
    case 'major':
      return _Version(
        major: current.major + 1,
        minor: 0,
        patch: 0,
        build: current.build + 1,
      );
    case 'build':
      return _Version(
        major: current.major,
        minor: current.minor,
        patch: current.patch,
        build: current.build + 1,
      );
    case 'set':
      if (args.length != 2) {
        _printUsageAndExit();
      }
      final match = _rawVersionPattern.firstMatch(args[1]);
      if (match == null) {
        stderr.writeln('set expects version in x.y.z+n format');
        exit(1);
      }
      return _Version(
        major: int.parse(match.group(1)!),
        minor: int.parse(match.group(2)!),
        patch: int.parse(match.group(3)!),
        build: int.parse(match.group(4)!),
      );
    default:
      _printUsageAndExit();
  }
}

Never _printUsageAndExit() {
  stderr.writeln(
    'Usage: dart run tool/bump_version.dart <patch|minor|major|build|set x.y.z+n>',
  );
  exit(64);
}

final class _Version {
  const _Version({
    required this.major,
    required this.minor,
    required this.patch,
    required this.build,
  });

  final int major;
  final int minor;
  final int patch;
  final int build;

  String get value => '$major.$minor.$patch+$build';
  String get name => '$major.$minor.$patch';
}
