import 'dart:typed_data';

import '../../core/runtime/file_read_isolate.dart';

Future<Uint8List> readMediaFileBytes(String path) =>
    readFileBytesInIsolate(path);
