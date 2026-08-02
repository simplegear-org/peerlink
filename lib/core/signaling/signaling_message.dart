class SignalingMessage {
  final String type;
  final String fromPeerId;
  final String toPeerId;
  final Map<String, dynamic> data;

  SignalingMessage({
    required this.type,
    required this.fromPeerId,
    required this.toPeerId,
    required this.data,
  });

  Map<String, dynamic> toJson() => {
        "type": type,
        "from": fromPeerId,
        "to": toPeerId,
        "data": data,
      };

  factory SignalingMessage.fromJson(Map<String, dynamic> json) {
    return SignalingMessage(
      type: json["type"],
      fromPeerId: json["from"],
      toPeerId: json["to"],
      data: Map<String, dynamic>.from(json["data"]),
    );
  }
}