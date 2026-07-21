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
