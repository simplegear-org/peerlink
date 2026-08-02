import 'dart:io';

class StorageServicePaths {
  const StorageServicePaths._();

  static Future<Directory> resolveRootDirectory() async {
    final home = Platform.environment['HOME'];
    final tmpDir = Platform.environment['TMPDIR'];
    if ((Platform.isIOS || Platform.isMacOS) &&
        home != null &&
        home.isNotEmpty) {
      final root = Directory('$home/Library/Application Support/peerlink');
      await root.create(recursive: true);
      return root;
    }

    try {
      if (home != null && home.isNotEmpty) {
        final root = Directory('$home/.peerlink');
        await root.create(recursive: true);
        return root;
      }
    } catch (_) {
      // Diagnostics disabled.
    }

    try {
      if (tmpDir != null && tmpDir.isNotEmpty) {
        final root = Directory('$tmpDir/peerlink');
        await root.create(recursive: true);
        return root;
      }
    } catch (_) {
      // Diagnostics disabled.
    }

    try {
      final currentPath = Directory.current.path;
      final safeCurrentPath = currentPath == '/'
          ? Directory.systemTemp.path
          : currentPath;
      final root = Directory('$safeCurrentPath/.peerlink');
      await root.create(recursive: true);
      return root;
    } catch (_) {
      // Diagnostics disabled.
    }

    final root = Directory('${Directory.systemTemp.path}/peerlink');
    await root.create(recursive: true);
    return root;
  }

  static String safeMediaFileName(String fileName) {
    return fileName.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
  }

  static Set<String> legacyMediaCandidateDirectories({
    required String peerId,
    String? previousPath,
  }) {
    final candidateDirs = <String>{};
    final prev = previousPath?.trim();
    if (prev != null && prev.isNotEmpty) {
      final prevParent = File(prev).parent.path;
      if (prevParent.isNotEmpty) {
        candidateDirs.add(prevParent);
      }
    }

    final home = Platform.environment['HOME'];
    if (home != null && home.isNotEmpty) {
      candidateDirs.add('$home/.peerlink/media/$peerId');
    }

    final tmpDir = Platform.environment['TMPDIR'];
    if (tmpDir != null && tmpDir.isNotEmpty) {
      candidateDirs.add('$tmpDir/peerlink/media/$peerId');
      candidateDirs.add('$tmpDir/.peerlink/media/$peerId');
    }

    final cwd = Directory.current.path;
    candidateDirs.add('$cwd/.peerlink/media/$peerId');
    candidateDirs.add('${Directory.systemTemp.path}/peerlink/media/$peerId');
    candidateDirs.add('${Directory.systemTemp.path}/.peerlink/media/$peerId');
    return candidateDirs;
  }
}
