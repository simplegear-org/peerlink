import 'package:flutter_test/flutter_test.dart';
import 'package:peerlink/core/runtime/app_file_logger.dart';

void main() {
  tearDown(() async {
    await AppFileLogger.setLogLevel(AppLogLevel.verbose, persist: false);
  });

  test('relay media diagnostics remain enabled in errors-only mode', () async {
    await AppFileLogger.setLogLevel(AppLogLevel.errorsOnly, persist: false);

    expect(
      AppFileLogger.shouldLog('[chat_media] message-persist-success'),
      isTrue,
    );
    expect(
      AppFileLogger.shouldLog('[relay_media] relay-download-progress'),
      isTrue,
    );
    expect(AppFileLogger.shouldLog('[invite] event=invite_completed'), isTrue);
    expect(AppFileLogger.shouldLog('[chat] ordinary success'), isFalse);
  });
}
