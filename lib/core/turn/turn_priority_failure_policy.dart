// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// SPDX-License-Identifier: MPL-2.0

import 'turn_server_config.dart';

/// Owns transient TURN connection-failure statistics and priority penalties.
///
/// Storage and reachability probing deliberately remain outside this policy.
class TurnPriorityFailurePolicy {
  final Map<String, int> _failureCounts = <String, int>{};
  final Map<String, DateTime> _lastFailureTime = <String, DateTime>{};
  final Map<String, int> _basePriorityByUrl = <String, int>{};

  void replaceBasePriorities(Iterable<TurnServerConfig> servers) {
    _basePriorityByUrl
      ..clear()
      ..addEntries(
        servers.map((server) => MapEntry(server.url, server.priority)),
      );
  }

  void rememberBasePriority(TurnServerConfig server) {
    _basePriorityByUrl[server.url] = server.priority;
  }

  void forget(String url) {
    _failureCounts.remove(url);
    _lastFailureTime.remove(url);
    _basePriorityByUrl.remove(url);
  }

  void reportFailure(String url, {DateTime? at}) {
    _failureCounts[url] = (_failureCounts[url] ?? 0) + 1;
    _lastFailureTime[url] = at ?? DateTime.now();
  }

  void reportSuccess(String url) {
    _failureCounts[url] = 0;
    _lastFailureTime.remove(url);
  }

  void reset() {
    _failureCounts.clear();
    _lastFailureTime.clear();
  }

  List<TurnServerConfig> apply(Iterable<TurnServerConfig> servers) {
    return servers
        .map((server) => server.copyWith(priority: priorityFor(server.url)))
        .toList(growable: false);
  }

  int priorityFor(String url) {
    final basePriority = _basePriorityByUrl[url] ?? 100;
    final failures = _failureCounts[url] ?? 0;
    if (failures == 0) {
      return basePriority;
    }
    return (basePriority - failures * 100).clamp(0, basePriority);
  }

  int failureCountFor(String url) => _failureCounts[url] ?? 0;

  DateTime? lastFailureFor(String url) => _lastFailureTime[url];
}
