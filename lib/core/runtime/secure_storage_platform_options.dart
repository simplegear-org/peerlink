// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// SPDX-License-Identifier: MPL-2.0

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

const peerLinkIOSStorageOptions = IOSOptions(
  accessibility: KeychainAccessibility.first_unlock_this_device,
);

const peerLinkMacOSStorageOptions = MacOsOptions(
  accessibility: KeychainAccessibility.first_unlock_this_device,
  usesDataProtectionKeychain: false,
);

const peerLinkSecureStorage = FlutterSecureStorage(
  iOptions: peerLinkIOSStorageOptions,
  mOptions: peerLinkMacOSStorageOptions,
);
