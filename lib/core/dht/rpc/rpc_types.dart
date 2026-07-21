class NodeInfo {
  final String nodeId;
  final String address;

  NodeInfo(this.nodeId, this.address);

  factory NodeInfo.fromJson(Map<String, dynamic> json) {
    return NodeInfo(
      json['nodeId'],
      json['address'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      "nodeId": nodeId,
      "address": address,
    };
  }
}

class RpcMessage {
  final String id;
  final String type;
  final Map<String, dynamic> payload;

  RpcMessage({
    required this.id,
    required this.type,
    required this.payload,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type,
      'payload': payload,
    };
  }

  factory RpcMessage.fromJson(Map<String, dynamic> json) {
    final rawPayload = json['payload'];
    final payload = rawPayload is Map<String, dynamic>
        ? Map<String, dynamic>.from(rawPayload)
        : <String, dynamic>{};
    return RpcMessage(
      id: json['id'] as String,
      type: json['type'] as String,
      payload: payload,
    );
  }
}
