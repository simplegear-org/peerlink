// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// SPDX-License-Identifier: MPL-2.0

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
