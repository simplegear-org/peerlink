// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// SPDX-License-Identifier: MPL-2.0

import '../runtime/secure_storage_wrapper.dart';

/// Абстракция хранилища ключей identity.
abstract class IdentityKeyStore {
  /// Читает сохраненное значение по ключу.
  Future<String?> read(String key);

  /// Записывает значение по ключу.
  Future<void> write(String key, String value);

  /// Удаляет сохраненное значение по ключу.
  Future<void> delete(String key);
}

/// Реализация хранилища ключей через общий storage wrapper с fallback.
class SecureIdentityKeyStore implements IdentityKeyStore {
  const SecureIdentityKeyStore();

  @override
  Future<String?> read(String key) => SecureStorageWrapper.read(key);

  @override
  Future<void> write(String key, String value) {
    return SecureStorageWrapper.write(key, value);
  }

  @override
  Future<void> delete(String key) => SecureStorageWrapper.delete(key);
}
