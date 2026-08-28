// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// SPDX-License-Identifier: MPL-2.0

import 'package:flutter/material.dart';

import '../localization/app_strings.dart';
import '../theme/app_theme.dart';

class TermsGateScreen extends StatelessWidget {
  final String version;
  final Future<void> Function() onAccept;

  const TermsGateScreen({
    super.key,
    required this.version,
    required this.onAccept,
  });

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(strings.termsTitle)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(strings.termsTitle, style: theme.textTheme.headlineSmall),
            const SizedBox(height: 8),
            Text(
              strings.termsVersion(version),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: AppTheme.muted,
              ),
            ),
            const SizedBox(height: 20),
            Text(strings.termsIntro, style: theme.textTheme.bodyLarge),
            const SizedBox(height: 16),
            _TermsBullet(text: strings.termsRuleRespect),
            _TermsBullet(text: strings.termsRuleReport),
            _TermsBullet(text: strings.termsRulePrivacy),
            _TermsBullet(text: strings.termsRuleRestriction),
            const SizedBox(height: 22),
            FilledButton.icon(
              onPressed: () => onAccept(),
              icon: const Icon(Icons.check_circle_outline),
              label: Text(strings.acceptTerms),
            ),
          ],
        ),
      ),
    );
  }
}

class _TermsBullet extends StatelessWidget {
  final String text;

  const _TermsBullet({required this.text});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 2),
            child: Icon(Icons.shield_outlined, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: theme.textTheme.bodyMedium)),
        ],
      ),
    );
  }
}
