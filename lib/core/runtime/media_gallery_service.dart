// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// SPDX-License-Identifier: MPL-2.0

import 'package:flutter/services.dart';

class MediaGalleryService {
  static const MethodChannel _channel = MethodChannel(
    'peerlink/media_gallery/methods',
  );

  const MediaGalleryService();

  Future<void> saveMediaIfMissing({
    required String filePath,
    required String fileName,
  }) async {
    await _channel.invokeMethod<void>('saveMediaIfMissing', {
      'filePath': filePath,
      'fileName': fileName,
    });
  }
}
