class Contact {

  final String peerId;
  final String name;

  Contact({
    required this.peerId,
    required this.name,
  });

  factory Contact.fromJson(Map<String, dynamic> json) {
    return Contact(
      peerId: json['peerId'] as String,
      name: json['name'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'peerId': peerId,
      'name': name,
    };
  }

  String shortId() {
    if (peerId.length <= 8) return peerId;
    return "${peerId.substring(0,4)}...${peerId.substring(peerId.length-4)}";
  }
}
