// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// SPDX-License-Identifier: MPL-2.0

import 'package:flutter/material.dart';

class SettingsScreenStyles {
  static const EdgeInsets screenPadding = EdgeInsets.fromLTRB(16, 0, 16, 28);
  static const EdgeInsets sectionPadding = EdgeInsets.symmetric(
    horizontal: 14,
    vertical: 11,
  );
  static const EdgeInsets listItemMargin = EdgeInsets.only(bottom: 6);
  static const EdgeInsets emptyLabelPadding = EdgeInsets.symmetric(vertical: 8);
  static const EdgeInsets listItemPadding = EdgeInsets.symmetric(
    horizontal: 14,
    vertical: 11,
  );

  static const double sectionRadius = 20;
  static const double itemRadius = 20;
  static const double itemHeight = 72;
  static const double cardSeparatorHeight = 6;
  static const double statusIndicatorSize = 12;
}
