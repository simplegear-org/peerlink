import 'package:flutter_test/flutter_test.dart';
import 'package:peerlink/core/security/account_identity.dart';

void main() {
  test('AccountIdentity serializes account id, display name, and devices', () {
    final identity = AccountIdentity(
      accountId: ' account-1 ',
      displayName: ' Alice ',
      devices: <AccountDeviceIdentity>[
        AccountDeviceIdentity(
          deviceId: 'device-1',
          peerId: 'peer-1',
          signingPublicKey: 'signing',
          agreementPublicKey: 'agreement',
          endpointId: 'endpoint',
          fcmTokenHash: 'token-hash',
          createdAtMs: 10,
          updatedAtMs: 20,
          isCurrentDevice: true,
        ),
      ],
    );

    final restored = AccountIdentity.fromJson(identity.toJson());

    expect(restored.accountId, 'account-1');
    expect(restored.displayName, 'Alice');
    expect(restored.devices, hasLength(1));
    expect(restored.devices.single.deviceId, 'device-1');
    expect(restored.devices.single.peerId, 'peer-1');
    expect(restored.devices.single.isCurrentDevice, isTrue);
  });

  test('upsertDevice replaces device and preserves createdAtMs', () {
    final identity = AccountIdentity(
      accountId: 'account-1',
      devices: <AccountDeviceIdentity>[
        AccountDeviceIdentity(
          deviceId: 'device-1',
          createdAtMs: 10,
          updatedAtMs: 20,
        ),
      ],
    );

    final updated = identity.upsertDevice(
      AccountDeviceIdentity(
        deviceId: 'device-1',
        endpointId: 'endpoint-2',
        createdAtMs: 30,
        updatedAtMs: 40,
      ),
    );

    expect(updated.devices, hasLength(1));
    expect(updated.devices.single.createdAtMs, 10);
    expect(updated.devices.single.updatedAtMs, 40);
    expect(updated.devices.single.endpointId, 'endpoint-2');
  });

  test('withCurrentDevice marks only requested device as current', () {
    final identity = AccountIdentity(
      accountId: 'account-1',
      devices: <AccountDeviceIdentity>[
        AccountDeviceIdentity(
          deviceId: 'device-1',
          createdAtMs: 10,
          updatedAtMs: 20,
          isCurrentDevice: true,
        ),
        AccountDeviceIdentity(
          deviceId: 'device-2',
          createdAtMs: 30,
          updatedAtMs: 40,
        ),
      ],
    );

    final updated = identity.withCurrentDevice('device-2');

    expect(updated.deviceById('device-1')!.isCurrentDevice, isFalse);
    expect(updated.deviceById('device-2')!.isCurrentDevice, isTrue);
  });
}
