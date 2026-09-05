// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// SPDX-License-Identifier: MPL-2.0

import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';

class SignatureService {
  final Ed25519 _ed25519 = Ed25519();

  Future<Uint8List> sign(Uint8List message, SimpleKeyPair keyPair) async {
    final signature = await _ed25519.sign(message, keyPair: keyPair);

    return Uint8List.fromList(signature.bytes);
  }

  Future<bool> verify(
    Uint8List message,
    Uint8List signatureBytes,
    SimplePublicKey publicKey,
  ) async {
    final signature = Signature(signatureBytes, publicKey: publicKey);

    return _ed25519.verify(message, signature: signature);
  }
}
