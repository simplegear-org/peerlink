// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// SPDX-License-Identifier: MPL-2.0

class CallSessionEpoch {
  const CallSessionEpoch._(this.value);

  factory CallSessionEpoch.initial() => const CallSessionEpoch._(0);

  final int value;

  CallSessionEpoch next() => CallSessionEpoch._(value + 1);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CallSessionEpoch &&
          runtimeType == other.runtimeType &&
          value == other.value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'CallSessionEpoch($value)';
}
