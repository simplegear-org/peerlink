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
