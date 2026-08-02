class RecordStore {
  final Map<String, String> _records = {};

  void put(String key, String value) {
    _records[key] = value;
  }

  String? get(String key) => _records[key];
}