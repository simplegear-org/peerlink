// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// SPDX-License-Identifier: MPL-2.0

String chatNotificationTypeForFile({
  required String fileName,
  String? mimeType,
}) {
  final mime = (mimeType ?? '').trim().toLowerCase();
  final name = fileName.trim().toLowerCase();
  if (mime.startsWith('image/')) {
    return 'photo';
  }
  if (mime.startsWith('video/')) {
    return 'video';
  }
  if (mime.startsWith('audio/') ||
      name.endsWith('.m4a') ||
      name.endsWith('.aac') ||
      name.endsWith('.mp3') ||
      name.endsWith('.wav') ||
      name.endsWith('.ogg') ||
      name.endsWith('.opus')) {
    return 'voice';
  }
  if (mime.contains('geo') ||
      mime.contains('gpx') ||
      mime.contains('kml') ||
      name.endsWith('.geojson') ||
      name.endsWith('.gpx') ||
      name.endsWith('.kml')) {
    return 'geo';
  }
  return 'file';
}
