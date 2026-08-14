// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// SPDX-License-Identifier: MPL-2.0

import 'package:flutter/material.dart';

class MediaViewerStyles {
  static const double imageMinScale = 0.8;
  static const double imageMaxScale = 4;
  static const double fallbackAspectRatio = 16 / 9;
  static const double playOverlaySize = 84;
  static const double playIconSize = 48;
  static const EdgeInsets controlsPadding = EdgeInsets.symmetric(
    horizontal: 12,
    vertical: 10,
  );
  static const EdgeInsets controlsPosition = EdgeInsets.fromLTRB(16, 0, 16, 20);
  static const double controlsRadius = 18;
}
