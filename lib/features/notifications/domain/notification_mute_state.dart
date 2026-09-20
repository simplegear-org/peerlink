// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// SPDX-License-Identifier: MPL-2.0

/// Independently configurable local notification mute channels.
enum NotificationMuteChannel {
  directMessage,
  directCall,
  groupMessage,
  groupCall;

  String get storageKey => switch (this) {
    NotificationMuteChannel.directMessage => 'mutedMessagePeerIds',
    NotificationMuteChannel.directCall => 'mutedCallPeerIds',
    NotificationMuteChannel.groupMessage => 'mutedMessageGroupIds',
    NotificationMuteChannel.groupCall => 'mutedCallGroupIds',
  };
}

/// Immutable local notification-mute preferences.
class NotificationMuteState {
  const NotificationMuteState._(this._mutedIdsByChannel);

  factory NotificationMuteState.empty() =>
      const NotificationMuteState._(<NotificationMuteChannel, Set<String>>{});

  factory NotificationMuteState.fromJson(Object? value) {
    if (value is! Map) {
      return NotificationMuteState.empty();
    }
    final mutedIdsByChannel = <NotificationMuteChannel, Set<String>>{};
    for (final channel in NotificationMuteChannel.values) {
      final rawIds = value[channel.storageKey];
      if (rawIds is! Iterable) {
        continue;
      }
      final ids = rawIds
          .whereType<String>()
          .map((id) => id.trim())
          .where((id) => id.isNotEmpty)
          .toSet();
      if (ids.isNotEmpty) {
        mutedIdsByChannel[channel] = ids;
      }
    }
    return NotificationMuteState._(mutedIdsByChannel);
  }

  final Map<NotificationMuteChannel, Set<String>> _mutedIdsByChannel;

  bool isMuted({required NotificationMuteChannel channel, required String id}) {
    return _mutedIdsByChannel[channel]?.contains(id.trim()) ?? false;
  }

  Set<String> mutedIdsFor(NotificationMuteChannel channel) =>
      Set.unmodifiable(_mutedIdsByChannel[channel] ?? const <String>{});

  NotificationMuteState withMuted({
    required NotificationMuteChannel channel,
    required String id,
    required bool muted,
  }) {
    final normalizedId = id.trim();
    if (normalizedId.isEmpty) {
      throw ArgumentError.value(id, 'id', 'Необходим непустой идентификатор');
    }
    final updated = <NotificationMuteChannel, Set<String>>{
      for (final entry in _mutedIdsByChannel.entries)
        entry.key: Set<String>.from(entry.value),
    };
    final ids = updated.putIfAbsent(channel, () => <String>{});
    if (muted) {
      ids.add(normalizedId);
    } else {
      ids.remove(normalizedId);
      if (ids.isEmpty) {
        updated.remove(channel);
      }
    }
    return NotificationMuteState._(updated);
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    for (final channel in NotificationMuteChannel.values)
      channel.storageKey: (mutedIdsFor(channel).toList()..sort()),
  };
}
