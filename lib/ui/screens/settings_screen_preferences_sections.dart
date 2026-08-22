// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// SPDX-License-Identifier: MPL-2.0

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/runtime/app_file_logger.dart';
import '../../core/runtime/source_metadata.dart';
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

class SettingsLegalSection extends StatelessWidget {
  final SettingsController controller;

  const SettingsLegalSection({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final strings = context.strings;
    return SettingsSectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(strings.aboutLegal, style: theme.textTheme.titleLarge),
          const SizedBox(height: 12),
          _LegalRow(
            label: 'PeerLink X',
            value: strings.version(controller.appVersionLabel),
          ),
          _LegalRow(
            label: strings.openSourceLicense,
            value:
                '${PeerLinkSourceMetadata.licenseName} '
                '(${PeerLinkSourceMetadata.license})',
          ),
          _LegalActionRow(
            label: strings.sourceCode,
            buttonLabel: strings.sourceForThisVersion,
            icon: Icons.open_in_new,
            onPressed: () => _openSourceUrl(context),
          ),
          _LegalActionRow(
            label: strings.thirdPartyLicenses,
            buttonLabel: strings.thirdPartyLicenses,
            icon: Icons.article_outlined,
            onPressed: () => showLicensePage(
              context: context,
              applicationName: 'PeerLink X',
              applicationVersion: controller.appVersionLabel,
              applicationLegalese:
                  '${PeerLinkSourceMetadata.licenseName} '
                  '(${PeerLinkSourceMetadata.license})',
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openSourceUrl(BuildContext context) async {
    final uri = Uri.parse(PeerLinkSourceMetadata.sourceUrl);
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(PeerLinkSourceMetadata.sourceUrl)));
    }
  }
}

class _LegalRow extends StatelessWidget {
  final String label;
  final String value;

  const _LegalRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: theme.textTheme.titleSmall),
          const SizedBox(height: 2),
          SelectableText(
            value,
            style: theme.textTheme.bodyMedium?.copyWith(color: AppTheme.muted),
          ),
        ],
      ),
    );
  }
}

class _LegalActionRow extends StatelessWidget {
  final String label;
  final String buttonLabel;
  final IconData icon;
  final VoidCallback onPressed;

  const _LegalActionRow({
    required this.label,
    required this.buttonLabel,
    required this.icon,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: theme.textTheme.titleSmall),
          const SizedBox(height: 6),
          OutlinedButton.icon(
            onPressed: onPressed,
            icon: Icon(icon),
            label: Text(buttonLabel),
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
