import 'dart:io';

final _pubspecVersionPattern = RegExp(
  r'^version:\s*([0-9]+)\.([0-9]+)\.([0-9]+)\+([0-9]+)\s*$',
);
final _rawVersionPattern = RegExp(
  r'^([0-9]+)\.([0-9]+)\.([0-9]+)\+([0-9]+)$',
);

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
  lines[versionIndex] = 'version: ${next.value}';
  pubspec.writeAsStringSync('${lines.join('\n')}\n');
  stdout.writeln(next.value);
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
}
