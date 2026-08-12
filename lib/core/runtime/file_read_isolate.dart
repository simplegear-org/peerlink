import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

Future<Uint8List> readFileBytesInIsolate(String path) {
  return Isolate.run(() {
    return TransferableTypedData.fromList(<Uint8List>[
      File(path).readAsBytesSync(),
    ]);
  }).then((data) => data.materialize().asUint8List());
}
