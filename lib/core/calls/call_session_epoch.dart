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
