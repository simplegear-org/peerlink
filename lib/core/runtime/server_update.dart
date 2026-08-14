// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// SPDX-License-Identifier: MPL-2.0

import '../turn/turn_server_config.dart';

class ServerUpdate {
  final List<String> bootstrap;
  final List<String> relay;
  final List<String> push;
  final List<TurnServerConfig> turn;
  final List<String> priorityBootstrap;
  final List<String> priorityRelay;
  final List<String> priorityPush;
  final List<TurnServerConfig> priorityTurn;

  const ServerUpdate({
    required this.bootstrap,
    required this.relay,
    required this.push,
    required this.turn,
    this.priorityBootstrap = const <String>[],
    this.priorityRelay = const <String>[],
    this.priorityPush = const <String>[],
    this.priorityTurn = const <TurnServerConfig>[],
  });

  bool get isEmpty =>
      bootstrap.isEmpty &&
      relay.isEmpty &&
      push.isEmpty &&
      turn.isEmpty &&
      priorityBootstrap.isEmpty &&
      priorityRelay.isEmpty &&
      priorityPush.isEmpty &&
      priorityTurn.isEmpty;
}
