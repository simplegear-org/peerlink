import 'dart:io';

final RegExp _importPattern = RegExp(r'''^\s*import\s+['"]([^'"]+)['"]''');

class DartSource {
  const DartSource({required this.path, required this.content});

  final String path;
  final String content;

  Iterable<ImportRecord> imports() sync* {
    final lines = content.split('\n');
    for (var i = 0; i < lines.length; i++) {
      final match = _importPattern.firstMatch(lines[i]);
      if (match == null) {
        continue;
      }
      yield ImportRecord(sourcePath: path, line: i + 1, uri: match.group(1)!);
    }
  }

  int countConstructorCalls(String className) {
    final pattern = RegExp(r'(?<!class\s)\b' + className + r'\s*\(');
    return pattern.allMatches(content).length;
  }

  bool containsConstructorCall(String className) {
    return countConstructorCalls(className) > 0;
  }
}

class ImportRecord {
  const ImportRecord({
    required this.sourcePath,
    required this.line,
    required this.uri,
  });

  final String sourcePath;
  final int line;
  final String uri;

  String? resolvePeerlinkPath() {
    if (uri.startsWith('package:peerlink/')) {
      return _normalize(uri.substring('package:peerlink/'.length));
    }
    if (!uri.endsWith('.dart')) {
      return null;
    }
    if (uri.startsWith('dart:') || uri.startsWith('package:')) {
      return null;
    }
    final parent = sourcePath.contains('/')
        ? sourcePath.substring(0, sourcePath.lastIndexOf('/'))
        : '.';
    return _normalize('$parent/$uri');
  }

  String get location => '$sourcePath:$line';
}

List<DartSource> dartSourcesUnder(Iterable<String> roots) {
  final result = <DartSource>[];
  for (final root in roots) {
    final directory = Directory(root);
    if (!directory.existsSync()) {
      continue;
    }
    for (final entity in directory.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) {
        continue;
      }
      final relativePath = _normalize(entity.path);
      result.add(
        DartSource(path: relativePath, content: entity.readAsStringSync()),
      );
    }
  }
  result.sort((a, b) => a.path.compareTo(b.path));
  return result;
}

Map<String, int> constructorCallCounts(
  Iterable<DartSource> sources,
  String className,
) {
  final counts = <String, int>{};
  for (final source in sources) {
    final count = source.countConstructorCalls(className);
    if (count > 0) {
      counts[source.path] = count;
    }
  }
  return counts;
}

List<String> constructorCallViolations(
  Iterable<DartSource> sources,
  Iterable<String> classNames,
) {
  final violations = <String>[];
  for (final source in sources) {
    for (final className in classNames) {
      if (source.containsConstructorCall(className)) {
        violations.add('${source.path}: constructs $className');
      }
    }
  }
  violations.sort();
  return violations;
}

String _normalize(String path) {
  final rawParts = path.replaceAll('\\', '/').split('/');
  final parts = <String>[];
  for (final part in rawParts) {
    if (part.isEmpty || part == '.') {
      continue;
    }
    if (part == '..') {
      if (parts.isNotEmpty) {
        parts.removeLast();
      }
      continue;
    }
    parts.add(part);
  }
  return parts.join('/');
}
