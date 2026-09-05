// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// SPDX-License-Identifier: MPL-2.0

import 'dart:typed_data';

import 'package:peerlink/core/runtime/file_read_isolate.dart';

Future<Uint8List> readMediaFileBytes(String path) =>
    readFileBytesInIsolate(path);
