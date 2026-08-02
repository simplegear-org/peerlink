import 'dart:io';

import 'storage_service_paths.dart';

class StorageServiceMedia {
  const StorageServiceMedia({
    required this.mediaDirectory,
    required this.loadAllChatSummaries,
    required this.readChatMessages,
    required this.writeChatMessages,
    required this.saveChatSummaryMap,
  });

  final Directory? mediaDirectory;
  final Future<List<Map<String, dynamic>>> Function() loadAllChatSummaries;
  final Future<List<Map<String, dynamic>>> Function(String peerId)
  readChatMessages;
  final Future<void> Function(String peerId, List<Map<String, dynamic>> messages)
  writeChatMessages;
  final Future<void> Function(String peerId, Map<String, dynamic> json)
  saveChatSummaryMap;

  Future<String> saveBytes({
    required String peerId,
    required String messageId,
    required String fileName,
    required List<int> bytes,
  }) async {
    try {
      final peerDir = await _ensurePeerDirectory(peerId);
      if (peerDir == null) {
        return '';
      }

      final safeName = StorageServicePaths.safeMediaFileName(fileName);
      final file = File('${peerDir.path}/$messageId-$safeName');
      await file.writeAsBytes(bytes, flush: true);
      return file.path;
    } catch (_) {
      return '';
    }
  }

  Future<String> saveFile({
    required String peerId,
    required String messageId,
    required String fileName,
    required String sourcePath,
  }) async {
    try {
      final sourceFile = File(sourcePath);
      if (!await sourceFile.exists()) {
        return '';
      }

      final peerDir = await _ensurePeerDirectory(peerId);
      if (peerDir == null) {
        return '';
      }

      final safeName = StorageServicePaths.safeMediaFileName(fileName);
      final destination = File('${peerDir.path}/$messageId-$safeName');
      if (await destination.exists()) {
        return destination.path;
      }

      await sourceFile.copy(destination.path);
      return destination.path;
    } catch (_) {
      return '';
    }
  }

  Future<void> deleteFile(String? path) async {
    if (path == null || path.isEmpty) {
      return;
    }

    try {
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {
      // Diagnostics disabled.
    }
  }

  Future<void> deletePeerDirectory(String peerId) async {
    try {
      final currentMediaDirectory = mediaDirectory;
      if (currentMediaDirectory == null) {
        return;
      }
      final directory = Directory('${currentMediaDirectory.path}/$peerId');
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
    } catch (_) {
      // Diagnostics disabled.
    }
  }

  bool isManagedPath(String? path) {
    if (path == null || path.isEmpty) {
      return false;
    }
    final currentMediaDirectory = mediaDirectory;
    if (currentMediaDirectory == null) {
      return false;
    }
    return path.startsWith('${currentMediaDirectory.path}/');
  }

  Future<void> clearManagedStorage() async {
    final summaries = await loadAllChatSummaries();
    for (final summary in summaries) {
      final peerId = (summary['peerId'] as String? ?? '').trim();
      if (peerId.isEmpty) {
        continue;
      }

      final messages = await readChatMessages(peerId);
      var changedMessages = false;
      for (final message in messages) {
        if ((message['localFilePath'] as String?)?.isNotEmpty == true) {
          message['localFilePath'] = null;
          changedMessages = true;
        }
      }
      if (changedMessages) {
        await writeChatMessages(peerId, messages);
      }

      if ((summary['avatarPath'] as String?)?.isNotEmpty == true) {
        final updated = Map<String, dynamic>.from(summary)
          ..['avatarPath'] = null;
        await saveChatSummaryMap(peerId, updated);
      }
    }

    final currentMediaDirectory = mediaDirectory;
    if (currentMediaDirectory != null && await currentMediaDirectory.exists()) {
      await currentMediaDirectory.delete(recursive: true);
      await currentMediaDirectory.create(recursive: true);
    }
  }

  Future<int> directorySize(Directory? directory) async {
    if (directory == null || !await directory.exists()) {
      return 0;
    }
    var total = 0;
    await for (final entity in directory.list(
      recursive: true,
      followLinks: false,
    )) {
      if (entity is! File) {
        continue;
      }
      try {
        total += await entity.length();
      } catch (_) {
        // Best effort size calculation.
      }
    }
    return total;
  }

  Future<String?> recoverLegacyMedia({
    required String peerId,
    required String messageId,
    required String fileName,
    String? previousPath,
  }) async {
    if (mediaDirectory == null) {
      return null;
    }

    final prev = previousPath?.trim();
    final safeName = StorageServicePaths.safeMediaFileName(fileName);
    final exactCandidates = <String>{
      '$messageId-$safeName',
      if (prev != null && prev.isNotEmpty) File(prev).uri.pathSegments.last,
    };
    final prefix = '$messageId-';

    File? source;
    for (final path in StorageServicePaths.legacyMediaCandidateDirectories(
      peerId: peerId,
      previousPath: previousPath,
    )) {
      source = await _findLegacySourceFile(
        directoryPath: path,
        exactCandidates: exactCandidates,
        prefix: prefix,
      );
      if (source != null) {
        break;
      }
    }

    if (source == null) {
      return null;
    }

    final copiedPath = await saveFile(
      peerId: peerId,
      messageId: messageId,
      fileName: fileName,
      sourcePath: source.path,
    );
    return copiedPath.isEmpty ? null : copiedPath;
  }

  Future<Directory?> _ensurePeerDirectory(String peerId) async {
    final currentMediaDirectory = mediaDirectory;
    if (currentMediaDirectory == null) {
      return null;
    }

    final peerDir = Directory('${currentMediaDirectory.path}/$peerId');
    await peerDir.create(recursive: true);
    return peerDir;
  }

  Future<File?> _findLegacySourceFile({
    required String directoryPath,
    required Set<String> exactCandidates,
    required String prefix,
  }) async {
    final dir = Directory(directoryPath);
    if (!await dir.exists()) {
      return null;
    }

    for (final name in exactCandidates) {
      if (name.isEmpty) {
        continue;
      }
      final file = File('${dir.path}/$name');
      if (await file.exists()) {
        return file;
      }
    }

    try {
      final entries = await dir.list().where((entity) {
        if (entity is! File) {
          return false;
        }
        final segments = entity.uri.pathSegments;
        final name = segments.isEmpty ? '' : segments.last;
        return name.startsWith(prefix);
      }).toList();
      if (entries.isNotEmpty) {
        return entries.first as File;
      }
    } catch (_) {
      // Best effort legacy restore.
    }

    return null;
  }
}
