import 'package:flutter/material.dart';

enum AppAppearance { icon1, icon2, icon3, icon4, icon5, icon6, icon7, icon8 }

class AppPalette {
  final Color sand;
  final Color paper;
  final Color ink;
  final Color muted;
  final Color stroke;
  final Color accent;
  final Color accentSoft;
  final Color pine;
  final Color pineSoft;
  final Color surfaceRaised;
  final Color surfaceMuted;

  const AppPalette({
    required this.sand,
    required this.paper,
    required this.ink,
    required this.muted,
    required this.stroke,
    required this.accent,
    required this.accentSoft,
    required this.pine,
    required this.pineSoft,
    required this.surfaceRaised,
    required this.surfaceMuted,
  });
}

extension AppAppearanceX on AppAppearance {
  String get storageKey => name;

  String get title => '${index + 1}';

  String get assetPath => 'assets/app_icon/icon_${index + 1}.png';

  AppPalette get palette {
    switch (this) {
      case AppAppearance.icon1:
        return const AppPalette(
          sand: Color(0xFF060D1A),
          paper: Color(0xFF101C33),
          ink: Color(0xFFF3F8FF),
          muted: Color(0xFF93A7C6),
          stroke: Color(0xFF21395F),
          accent: Color(0xFF4C8CFF),
          accentSoft: Color(0xFF173765),
          pine: Color(0xFF59D7C7),
          pineSoft: Color(0xFF14313D),
          surfaceRaised: Color(0xFF142440),
          surfaceMuted: Color(0xFF0B162B),
        );
      case AppAppearance.icon2:
        return const AppPalette(
          sand: Color(0xFF090A0D),
          paper: Color(0xFF161920),
          ink: Color(0xFFF5F7FB),
          muted: Color(0xFFADB4C1),
          stroke: Color(0xFF2A2F3A),
          accent: Color(0xFFB8C4D9),
          accentSoft: Color(0xFF252B35),
          pine: Color(0xFF7EE0D3),
          pineSoft: Color(0xFF162B2C),
          surfaceRaised: Color(0xFF1C2028),
          surfaceMuted: Color(0xFF12151B),
        );
      case AppAppearance.icon3:
        return const AppPalette(
          sand: Color(0xFF041312),
          paper: Color(0xFF0D2326),
          ink: Color(0xFFF1FFFD),
          muted: Color(0xFF93BFB9),
          stroke: Color(0xFF1E4A4E),
          accent: Color(0xFF2FD7C4),
          accentSoft: Color(0xFF124147),
          pine: Color(0xFF84F0B2),
          pineSoft: Color(0xFF10332B),
          surfaceRaised: Color(0xFF123137),
          surfaceMuted: Color(0xFF091B1D),
        );
      case AppAppearance.icon4:
        return const AppPalette(
          sand: Color(0xFF100B1D),
          paper: Color(0xFF1B1531),
          ink: Color(0xFFF8F4FF),
          muted: Color(0xFFB2A6CC),
          stroke: Color(0xFF3A2E63),
          accent: Color(0xFF9B74FF),
          accentSoft: Color(0xFF34235E),
          pine: Color(0xFF6ED9E8),
          pineSoft: Color(0xFF183445),
          surfaceRaised: Color(0xFF261D45),
          surfaceMuted: Color(0xFF161129),
        );
      case AppAppearance.icon5:
        return const AppPalette(
          sand: Color(0xFF1A1000),
          paper: Color(0xFF2A1B05),
          ink: Color(0xFFFFFAEC),
          muted: Color(0xFFD7B879),
          stroke: Color(0xFF5E3B08),
          accent: Color(0xFFF0B000),
          accentSoft: Color(0xFF5A3800),
          pine: Color(0xFFFFD45A),
          pineSoft: Color(0xFF4B3108),
          surfaceRaised: Color(0xFF3A2606),
          surfaceMuted: Color(0xFF201404),
        );
      case AppAppearance.icon6:
        return const AppPalette(
          sand: Color(0xFF0B1400),
          paper: Color(0xFF152407),
          ink: Color(0xFFF7FFE9),
          muted: Color(0xFFB8D184),
          stroke: Color(0xFF355810),
          accent: Color(0xFF9DDF1E),
          accentSoft: Color(0xFF314D0B),
          pine: Color(0xFF76D925),
          pineSoft: Color(0xFF203A12),
          surfaceRaised: Color(0xFF21360A),
          surfaceMuted: Color(0xFF101B05),
        );
      case AppAppearance.icon7:
        return const AppPalette(
          sand: Color(0xFF020B18),
          paper: Color(0xFF071A35),
          ink: Color(0xFFF0F8FF),
          muted: Color(0xFF91B7E0),
          stroke: Color(0xFF123E70),
          accent: Color(0xFF0086F4),
          accentSoft: Color(0xFF073D73),
          pine: Color(0xFF20C7FF),
          pineSoft: Color(0xFF06354E),
          surfaceRaised: Color(0xFF0A2A55),
          surfaceMuted: Color(0xFF041225),
        );
      case AppAppearance.icon8:
        return const AppPalette(
          sand: Color(0xFF17110A),
          paper: Color(0xFF2A2117),
          ink: Color(0xFFFFF6E5),
          muted: Color(0xFFD5C0A0),
          stroke: Color(0xFF594734),
          accent: Color(0xFFE4C39C),
          accentSoft: Color(0xFF4A3827),
          pine: Color(0xFFF0D8B8),
          pineSoft: Color(0xFF403123),
          surfaceRaised: Color(0xFF382B1E),
          surfaceMuted: Color(0xFF21180F),
        );
    }
  }

  static AppAppearance fromStorageKey(String? value) {
    switch (value) {
      case 'blue':
        return AppAppearance.icon1;
      case 'black':
        return AppAppearance.icon2;
      case 'turquoise':
        return AppAppearance.icon3;
      case 'violet':
        return AppAppearance.icon4;
    }
    return AppAppearance.values.firstWhere(
      (item) => item.storageKey == value,
      orElse: () => AppAppearance.icon1,
    );
  }
}
