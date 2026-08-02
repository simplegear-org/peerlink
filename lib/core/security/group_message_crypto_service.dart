import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'group_key_service.dart';

class GroupMessageCryptoService {
  static const List<int> _groupMediaCipherMagicV2 = <int>[
    0x50,
    0x4C,
    0x47,
    0x32,
  ]; // PLG2

  final GroupKeyService groupKeyService;
  final String securePayloadPrefix;
  final Cipher _groupCipher = AesGcm.with256bits();

  GroupMessageCryptoService({
    required this.groupKeyService,
    required this.securePayloadPrefix,
  });

  Future<String?> encryptGroupText({
    required String groupId,
    required String plainText,
  }) async {
    final keyBase64 = groupKeyService.keyForGroup(groupId);
    if (keyBase64 == null || keyBase64.isEmpty) {
      return null;
    }
    final keyBytes = base64Decode(keyBase64);
    if (keyBytes.length != 32) {
      return null;
    }
    final secretKey = SecretKey(keyBytes);
    final nonce = _groupCipher.newNonce();
    final clear = Uint8List.fromList(utf8.encode(plainText));
    final secretBox = await _groupCipher.encrypt(
      clear,
      secretKey: secretKey,
      nonce: nonce,
    );
    final payload = <String, dynamic>{
      'v': 1,
      'groupId': groupId,
      'nonce': base64Encode(secretBox.nonce),
      'cipher': base64Encode(secretBox.cipherText),
      'mac': base64Encode(secretBox.mac.bytes),
    };
    return '$securePayloadPrefix${jsonEncode(payload)}';
  }

  Future<String?> decryptGroupText(String text) async {
    if (!text.startsWith(securePayloadPrefix)) {
      return null;
    }
    final payloadText = text.substring(securePayloadPrefix.length);
    Map<String, dynamic> payload;
    try {
      final decoded = jsonDecode(payloadText);
      if (decoded is! Map<String, dynamic>) {
        return null;
      }
      payload = decoded;
    } catch (_) {
      return null;
    }
    final groupId = (payload['groupId'] as String? ?? '').trim();
    if (groupId.isEmpty) {
      return null;
    }
    final keyBase64 = groupKeyService.keyForGroup(groupId);
    if (keyBase64 == null || keyBase64.isEmpty) {
      return null;
    }
    final nonceRaw = payload['nonce'] as String?;
    final cipherRaw = payload['cipher'] as String?;
    final macRaw = payload['mac'] as String?;
    if (nonceRaw == null || cipherRaw == null || macRaw == null) {
      return null;
    }
    final keyBytes = base64Decode(keyBase64);
    if (keyBytes.length != 32) {
      return null;
    }
    final secretBox = SecretBox(
      base64Decode(cipherRaw),
      nonce: base64Decode(nonceRaw),
      mac: Mac(base64Decode(macRaw)),
    );
    final clear = await _groupCipher.decrypt(
      secretBox,
      secretKey: SecretKey(keyBytes),
    );
    return utf8.decode(clear);
  }

  Future<Uint8List?> encryptGroupBytes({
    required String groupId,
    required Uint8List plainBytes,
  }) async {
    final keyBase64 = groupKeyService.keyForGroup(groupId);
    if (keyBase64 == null || keyBase64.isEmpty) {
      return null;
    }
    if (plainBytes.length >= 256 * 1024) {
      return Isolate.run(
        () => _encryptGroupBytesIsolate(
          groupId: groupId,
          keyBase64: keyBase64,
          plainBytes: plainBytes,
        ),
      );
    }
    return _encryptGroupBytesIsolate(
      groupId: groupId,
      keyBase64: keyBase64,
      plainBytes: plainBytes,
    );
  }

  Future<Uint8List?> decryptGroupBytes({
    required String groupId,
    required Uint8List encryptedBytes,
  }) async {
    final keyBase64 = groupKeyService.keyForGroup(groupId);
    if (keyBase64 == null || keyBase64.isEmpty) {
      return null;
    }
    if (encryptedBytes.length >= 256 * 1024) {
      return Isolate.run(
        () => _decryptGroupBytesIsolate(
          groupId: groupId,
          keyBase64: keyBase64,
          encryptedBytes: encryptedBytes,
        ),
      );
    }
    return _decryptGroupBytesIsolate(
      groupId: groupId,
      keyBase64: keyBase64,
      encryptedBytes: encryptedBytes,
    );
  }

  Future<Uint8List> decodeGroupBlobBytes({
    required String groupId,
    required Uint8List encryptedBytes,
  }) async {
    final decrypted = await decryptGroupBytes(
      groupId: groupId,
      encryptedBytes: encryptedBytes,
    );
    return decrypted ?? encryptedBytes;
  }
}

Future<Uint8List?> _encryptGroupBytesIsolate({
  required String groupId,
  required String keyBase64,
  required Uint8List plainBytes,
}) async {
  final keyBytes = base64Decode(keyBase64);
  if (keyBytes.length != 32) {
    return null;
  }
  final cipher = AesGcm.with256bits();
  final secretKey = SecretKey(keyBytes);
  final nonce = cipher.newNonce();
  final secretBox = await cipher.encrypt(
    plainBytes,
    secretKey: secretKey,
    nonce: nonce,
  );
  final groupIdBytes = Uint8List.fromList(utf8.encode(groupId));
  final nonceBytes = Uint8List.fromList(secretBox.nonce);
  final macBytes = Uint8List.fromList(secretBox.mac.bytes);
  final cipherBytes = Uint8List.fromList(secretBox.cipherText);
  if (groupIdBytes.length > 0xFFFF ||
      nonceBytes.length > 0xFF ||
      macBytes.length > 0xFF) {
    return null;
  }

  final totalLength =
      GroupMessageCryptoService._groupMediaCipherMagicV2.length +
      1 +
      1 +
      2 +
      groupIdBytes.length +
      nonceBytes.length +
      macBytes.length +
      cipherBytes.length;
  final packed = Uint8List(totalLength);
  final data = ByteData.sublistView(packed);
  var offset = 0;
  for (final byte in GroupMessageCryptoService._groupMediaCipherMagicV2) {
    packed[offset++] = byte;
  }
  packed[offset++] = nonceBytes.length;
  packed[offset++] = macBytes.length;
  data.setUint16(offset, groupIdBytes.length, Endian.big);
  offset += 2;
  packed.setRange(offset, offset + groupIdBytes.length, groupIdBytes);
  offset += groupIdBytes.length;
  packed.setRange(offset, offset + nonceBytes.length, nonceBytes);
  offset += nonceBytes.length;
  packed.setRange(offset, offset + macBytes.length, macBytes);
  offset += macBytes.length;
  packed.setRange(offset, offset + cipherBytes.length, cipherBytes);
  return packed;
}

Future<Uint8List?> _decryptGroupBytesIsolate({
  required String groupId,
  required String keyBase64,
  required Uint8List encryptedBytes,
}) async {
  final keyBytes = base64Decode(keyBase64);
  if (keyBytes.length != 32) {
    return null;
  }
  final cipher = AesGcm.with256bits();
  final secretKey = SecretKey(keyBytes);

  if (encryptedBytes.length >=
      GroupMessageCryptoService._groupMediaCipherMagicV2.length +
          1 +
          1 +
          2 +
          1) {
    var magicMatch = true;
    for (
      var i = 0;
      i < GroupMessageCryptoService._groupMediaCipherMagicV2.length;
      i++
    ) {
      if (encryptedBytes[i] !=
          GroupMessageCryptoService._groupMediaCipherMagicV2[i]) {
        magicMatch = false;
        break;
      }
    }
    if (magicMatch) {
      var offset = GroupMessageCryptoService._groupMediaCipherMagicV2.length;
      final nonceLen = encryptedBytes[offset++];
      final macLen = encryptedBytes[offset++];
      final data = ByteData.sublistView(encryptedBytes);
      final groupIdLen = data.getUint16(offset, Endian.big);
      offset += 2;
      final minLength =
          GroupMessageCryptoService._groupMediaCipherMagicV2.length +
          1 +
          1 +
          2 +
          groupIdLen +
          nonceLen +
          macLen;
      if (encryptedBytes.length > minLength) {
        final groupIdEnd = offset + groupIdLen;
        if (groupIdEnd <= encryptedBytes.length) {
          final payloadGroupId = utf8.decode(
            encryptedBytes.sublist(offset, groupIdEnd),
            allowMalformed: true,
          );
          if (payloadGroupId == groupId) {
            offset = groupIdEnd;
            final nonceEnd = offset + nonceLen;
            final macEnd = nonceEnd + macLen;
            if (macEnd <= encryptedBytes.length) {
              final nonce = encryptedBytes.sublist(offset, nonceEnd);
              final macBytes = encryptedBytes.sublist(nonceEnd, macEnd);
              final payloadCipher = encryptedBytes.sublist(macEnd);
              if (payloadCipher.isNotEmpty) {
                final secretBox = SecretBox(
                  payloadCipher,
                  nonce: nonce,
                  mac: Mac(macBytes),
                );
                final clear = await cipher.decrypt(
                  secretBox,
                  secretKey: secretKey,
                );
                return Uint8List.fromList(clear);
              }
            }
          }
        }
      }
    }
  }

  Map<String, dynamic> payload;
  try {
    final decoded = jsonDecode(utf8.decode(encryptedBytes));
    if (decoded is Map<String, dynamic>) {
      payload = decoded;
    } else if (decoded is Map) {
      payload = Map<String, dynamic>.from(decoded);
    } else {
      return null;
    }
  } catch (_) {
    return null;
  }

  final payloadGroupId = (payload['groupId'] as String? ?? '').trim();
  if (payloadGroupId != groupId) {
    return null;
  }
  final nonceRaw = payload['nonce'] as String?;
  final cipherRaw = payload['cipher'] as String?;
  final macRaw = payload['mac'] as String?;
  if (nonceRaw == null || cipherRaw == null || macRaw == null) {
    return null;
  }

  final secretBox = SecretBox(
    base64Decode(cipherRaw),
    nonce: base64Decode(nonceRaw),
    mac: Mac(base64Decode(macRaw)),
  );
  final clear = await cipher.decrypt(secretBox, secretKey: secretKey);
  return Uint8List.fromList(clear);
}
