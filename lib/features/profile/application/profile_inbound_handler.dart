// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// SPDX-License-Identifier: MPL-2.0

import 'package:peerlink/features/profile/application/profile_avatar_inbound_handler.dart';
import 'package:peerlink/features/profile/application/profile_metadata_inbound_handler.dart';

abstract interface class ProfileInboundHandler
    implements ProfileAvatarInboundHandler, ProfileMetadataInboundHandler {}
