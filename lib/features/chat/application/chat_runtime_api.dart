// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// SPDX-License-Identifier: MPL-2.0

import 'package:peerlink/core/node/node_capability_apis.dart';

abstract interface class ChatRuntimeApi
    implements
        IdentityApi,
        MessagingApi,
        NetworkApi,
        CallsApi,
        ModerationApi,
        RuntimeEventsApi {}
