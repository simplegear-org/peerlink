// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// SPDX-License-Identifier: MPL-2.0

import 'server_availability.dart';

/// Common contract for runtime services that probe and publish server health.
///
/// Concrete implementations keep the server-type-specific probe logic
/// (`bootstrap`, `relay`, `turn`, `push`), while orchestration layers can work with
/// them uniformly through this interface.
abstract class ServerAvailabilityProvider {
  /// Stable provider identifier (`bootstrap`, `relay`, `turn`, `push`, ...).
  String get providerKey;

  /// Current ordered list of configured server ids for this provider.
  ///
  /// For `bootstrap` and `relay` this is the endpoint string.
  /// For `turn` this is the normalized TURN URL.
  /// For `push` this is the normalized push base URL.
  List<String> get serverKeys;

  /// Broadcast stream of the latest availability snapshot.
  Stream<Map<String, ServerAvailability>> get availabilityStream;

  /// Latest in-memory availability snapshot.
  Map<String, ServerAvailability> get availabilitySnapshot;

  /// Current availability for a single configured server.
  ServerAvailability availabilityFor(String serverKey);

  /// Loads configuration, applies it to runtime, and starts background probing.
  Future<void> initialize();

  /// Performs an immediate availability refresh.
  Future<void> refreshAvailability();

  /// Releases timers/streams used by the provider.
  void dispose();
}
