import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:peerlink/features/invites/infrastructure/android_install_referrer_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('peerlink/deep_links/methods');

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test(
    'accepts only a valid deferred invite token and acknowledges it',
    () async {
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            if (call.method == 'getInstallReferrerInviteToken') {
              return 'abcdefghijklmnopqrstuv';
            }
            return null;
          });

      final service = AndroidInstallReferrerService.instance;
      final token = await service.readInviteToken();
      expect(token, 'abcdefghijklmnopqrstuv');
      await service.markInviteTokenHandled(token!);
      expect(calls.last.method, 'markInstallReferrerInviteTokenHandled');
      expect(calls.last.arguments, token);
    },
  );

  test('rejects malformed install-referrer values', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async => 'not-a-token');

    expect(
      await AndroidInstallReferrerService.instance.readInviteToken(),
      isNull,
    );
  });
}
