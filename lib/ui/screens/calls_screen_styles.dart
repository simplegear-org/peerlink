import 'package:flutter/material.dart';

import '../widgets/compact_card_tile_styles.dart';

class CallsScreenStyles {
  static const EdgeInsets emptyOuterPadding = EdgeInsets.all(24);
  static const EdgeInsets emptyInnerPadding = EdgeInsets.all(28);
  static const EdgeInsets tilePadding = CompactCardTileStyles.tilePadding;
  static const EdgeInsets missedPillPadding =
      CompactCardTileStyles.badgePadding;

  static const double emptyCardRadius = 28;
  static const double emptyIconRadius = 24;
  static const double tileRadius = CompactCardTileStyles.tileRadius;
  static const double statusIconRadius = 14;
  static const double roundPillRadius = 999;

  static const double iconBoxSize = 76;
  static const double iconSize = 34;
  static const double statusIconBoxSize = CompactCardTileStyles.avatarSize;
  static const double statusIconSize = 22;
  static const double callActionSize = CompactCardTileStyles.trailingIconSize;
  static const double tileHorizontalGap = CompactCardTileStyles.horizontalGap;
  static const double textGap = CompactCardTileStyles.textGap;
  static const double tileSeparatorHeight =
      CompactCardTileStyles.tileSeparatorHeight;
}
