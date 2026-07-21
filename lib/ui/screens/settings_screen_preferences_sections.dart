import 'package:flutter/material.dart';

import '../../core/runtime/app_file_logger.dart';
import '../localization/app_language.dart';
import '../localization/app_strings.dart';
import '../state/app_appearance_controller.dart';
import '../state/app_locale_controller.dart';
import '../state/settings_controller.dart';
import '../theme/app_appearance.dart';
import '../theme/app_theme.dart';
import 'settings_screen_shared_widgets.dart';

class SettingsAppearanceSection extends StatelessWidget {
  final AppAppearanceController appearanceController;

  const SettingsAppearanceSection({
    super.key,
    required this.appearanceController,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final strings = context.strings;
    return AnimatedBuilder(
      animation: appearanceController,
      builder: (context, child) {
        final current = appearanceController.current;
        return SettingsSectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(strings.appAppearance, style: theme.textTheme.titleLarge),
              const SizedBox(height: 4),
              Text(
                strings.appAppearanceDescription,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: AppTheme.muted,
                ),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  for (final appearance in AppAppearance.values)
                    _AppearanceOption(
                      appearance: appearance,
                      selected: appearance == current,
                      onTap: () => appearanceController.select(appearance),
                    ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class SettingsLanguageSection extends StatelessWidget {
  final AppLocaleController localeController;

  const SettingsLanguageSection({super.key, required this.localeController});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final strings = context.strings;
    return AnimatedBuilder(
      animation: localeController,
      builder: (context, child) {
        final current = localeController.current;
        return SettingsSectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(strings.language, style: theme.textTheme.titleLarge),
              const SizedBox(height: 4),
              Text(
                strings.languageDescription,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: AppTheme.muted,
                ),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final language in AppLanguage.values)
                    _LanguageButton(
                      language: language,
                      selected: language == current,
                      onTap: language == current
                          ? null
                          : () => localeController.select(language),
                    ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class SettingsAppLogSection extends StatelessWidget {
  final SettingsController controller;
  final Future<void> Function() onShowAppLogPreview;
  final Future<void> Function() onShareAppLog;
  final Future<void> Function() onClearAppLog;
  final Future<void> Function(AppLogLevel level) onSetAppLogLevel;

  const SettingsAppLogSection({
    super.key,
    required this.controller,
    required this.onShowAppLogPreview,
    required this.onShareAppLog,
    required this.onClearAppLog,
    required this.onSetAppLogLevel,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final strings = context.strings;
    final currentLevel = controller.appLogLevel;
    return SettingsSectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(strings.appLog, style: theme.textTheme.titleLarge),
          const SizedBox(height: 4),
          Text(
            strings.appLogDescription,
            style: theme.textTheme.bodyMedium?.copyWith(color: AppTheme.muted),
          ),
          const SizedBox(height: 12),
          Text(strings.logLevel, style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _LogLevelChip(
                label: strings.logLevelErrorsOnly,
                selected: currentLevel == AppLogLevel.errorsOnly,
                onTap: currentLevel == AppLogLevel.errorsOnly
                    ? null
                    : () => onSetAppLogLevel(AppLogLevel.errorsOnly),
              ),
              _LogLevelChip(
                label: strings.logLevelVerbose,
                selected: currentLevel == AppLogLevel.verbose,
                onTap: currentLevel == AppLogLevel.verbose
                    ? null
                    : () => onSetAppLogLevel(AppLogLevel.verbose),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: () => onShowAppLogPreview(),
                icon: const Icon(Icons.article_outlined),
                label: Text(strings.showLog),
              ),
              OutlinedButton.icon(
                onPressed: () => onShareAppLog(),
                icon: const Icon(Icons.ios_share_outlined),
                label: Text(strings.shareLog),
              ),
              OutlinedButton.icon(
                onPressed: () => onClearAppLog(),
                icon: const Icon(Icons.delete_outline),
                label: Text(strings.clearLog),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class SettingsDataResetSection extends StatelessWidget {
  final Future<void> Function() onConfirmResetLocalAccount;
  final Future<void> Function() onConfirmResetDeviceCompletely;

  const SettingsDataResetSection({
    super.key,
    required this.onConfirmResetLocalAccount,
    required this.onConfirmResetDeviceCompletely,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final strings = context.strings;
    return SettingsSectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(strings.dataResetTitle, style: theme.textTheme.titleLarge),
          const SizedBox(height: 4),
          Text(
            strings.dataResetDescription,
            style: theme.textTheme.bodyMedium?.copyWith(color: AppTheme.muted),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: () => onConfirmResetLocalAccount(),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.red.shade700,
                  side: BorderSide(color: Colors.red.shade300),
                ),
                icon: const Icon(Icons.person_remove_outlined),
                label: Text(strings.resetLocalAccount),
              ),
              OutlinedButton.icon(
                onPressed: () => onConfirmResetDeviceCompletely(),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.red.shade700,
                  side: BorderSide(color: Colors.red.shade300),
                ),
                icon: const Icon(Icons.warning_amber_rounded),
                label: Text(strings.resetDeviceCompletely),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class SettingsVersionFooter extends StatelessWidget {
  final SettingsController controller;

  const SettingsVersionFooter({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        context.strings.version(controller.appVersionLabel),
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: AppTheme.muted,
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}

class _LogLevelChip extends StatelessWidget {
  final String label;
  final bool selected;
  final Future<void> Function()? onTap;

  const _LogLevelChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: onTap == null ? null : (_) => onTap!.call(),
      labelStyle: Theme.of(context).textTheme.labelLarge?.copyWith(
        color: selected ? AppTheme.paper : AppTheme.ink,
        fontWeight: FontWeight.w700,
      ),
      selectedColor: AppTheme.accent,
      backgroundColor: AppTheme.paper,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: selected ? AppTheme.accent : AppTheme.stroke),
      ),
      showCheckmark: false,
    );
  }
}

class _AppearanceOption extends StatelessWidget {
  final AppAppearance appearance;
  final bool selected;
  final Future<void> Function() onTap;

  const _AppearanceOption({
    required this.appearance,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final palette = appearance.palette;
    return InkWell(
      borderRadius: BorderRadius.circular(22),
      onTap: () => onTap(),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: 64,
        padding: const EdgeInsets.all(7),
        decoration: BoxDecoration(
          color: selected ? AppTheme.surfaceRaised : AppTheme.surfaceMuted,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: selected ? AppTheme.accent : AppTheme.stroke,
            width: selected ? 1.6 : 1,
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: AppTheme.accent.withValues(alpha: 0.22),
                    blurRadius: 16,
                    spreadRadius: 1,
                  ),
                ]
              : null,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [palette.accent, palette.accentSoft],
                ),
                border: Border.all(
                  color: palette.stroke.withValues(alpha: 0.8),
                ),
                boxShadow: [
                  BoxShadow(
                    color: palette.accent.withValues(alpha: 0.28),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Center(
                child: Container(
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(
                    color: palette.paper.withValues(alpha: 0.92),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.palette_outlined,
                    size: 16,
                    color: palette.accent,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LanguageButton extends StatelessWidget {
  final AppLanguage language;
  final bool selected;
  final Future<void> Function()? onTap;

  const _LanguageButton({
    required this.language,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return OutlinedButton(
      onPressed: onTap == null ? null : () => onTap!(),
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        foregroundColor: selected ? AppTheme.accent : AppTheme.ink,
        side: BorderSide(color: selected ? AppTheme.accent : AppTheme.stroke),
        backgroundColor: selected ? AppTheme.accentSoft : AppTheme.surfaceMuted,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
      child: Text(
        language.shortLabel,
        style: theme.textTheme.labelLarge?.copyWith(
          color: selected ? AppTheme.accent : AppTheme.ink,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}
