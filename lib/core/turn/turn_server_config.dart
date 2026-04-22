class TurnServerConfig {
  final String url;
  final String username;
  final String password;
  final int priority;

  const TurnServerConfig({
    required this.url,
    required this.username,
    required this.password,
    this.priority = 100,
  });

  Map<String, dynamic> toJson() => {
        'url': url,
        'username': username,
        'password': password,
        'priority': priority,
      };

  factory TurnServerConfig.fromJson(Map<String, dynamic> json) {
    return TurnServerConfig(
      url: json['url']?.toString() ?? '',
      username: json['username']?.toString() ?? '',
      password: json['password']?.toString() ?? '',
      priority: json['priority'] is int
          ? json['priority'] as int
          : int.tryParse(json['priority']?.toString() ?? '') ?? 100,
    );
  }

  TurnServerConfig copyWith({
    String? url,
    String? username,
    String? password,
    int? priority,
  }) {
    return TurnServerConfig(
      url: url ?? this.url,
      username: username ?? this.username,
      password: password ?? this.password,
      priority: priority ?? this.priority,
    );
  }
}
