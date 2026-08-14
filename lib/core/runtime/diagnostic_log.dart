// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// SPDX-License-Identifier: MPL-2.0

import 'dart:async';
import 'dart:developer' as developer;

import 'app_file_logger.dart';

void log(
  String message, {
  String name = '',
  DateTime? time,
  int? sequenceNumber,
  int level = 0,
  Object? error,
  StackTrace? stackTrace,
  Zone? zone,
}) {
  if (!AppFileLogger.shouldLog(
    message,
    error: error,
    stackTrace: stackTrace,
    level: level,
  )) {
    return;
  }
  developer.log(
    message,
    name: name,
    time: time,
    sequenceNumber: sequenceNumber,
    level: level,
    error: error,
    stackTrace: stackTrace,
    zone: zone,
  );
}
