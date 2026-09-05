// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// SPDX-License-Identifier: MPL-2.0

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
