// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// SPDX-License-Identifier: MPL-2.0

import 'package:flutter/material.dart';

import '../../core/node/node_facade.dart';
import '../../core/runtime/moderation_policy_service.dart';
import '../localization/app_strings.dart';
import '../theme/app_theme.dart';

class AccountRestrictedScreen extends StatefulWidget {
  final ModerationPolicySnapshot policy;
  final NodeFacade facade;
  final Future<void> Function() onAppealSubmitted;
  final Future<void> Function() onWarningContinued;

  const AccountRestrictedScreen({
    super.key,
    required this.policy,
    required this.facade,
    required this.onAppealSubmitted,
    required this.onWarningContinued,
  });

  @override
  State<AccountRestrictedScreen> createState() =>
      _AccountRestrictedScreenState();
}

class _AccountRestrictedScreenState extends State<AccountRestrictedScreen> {
  final TextEditingController _controller = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final theme = Theme.of(context);
    final isWarning = widget.policy.isWarning;
    final title = isWarning
        ? strings.moderationWarningTitle
        : strings.accountRestrictedTitle;
    final message = isWarning
        ? strings.moderationWarningMessage(
            reportCount: widget.policy.reportCount,
            reporterCount: widget.policy.reporterCount,
          )
        : widget.policy.messageKey == 'moderationBanMessage'
        ? strings.moderationBanMessage(
            reportCount: widget.policy.reportCount,
            reporterCount: widget.policy.reporterCount,
          )
        : (widget.policy.message.isNotEmpty
              ? widget.policy.message
              : strings.accountRestrictedDescription);
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Icon(
              isWarning ? Icons.warning_amber_rounded : Icons.gpp_bad_outlined,
              size: 44,
              color: theme.colorScheme.error,
            ),
            const SizedBox(height: 16),
            Text(title, style: theme.textTheme.headlineSmall),
            const SizedBox(height: 10),
            Text(message, style: theme.textTheme.bodyLarge),
            if (!isWarning) ...[
              const SizedBox(height: 18),
              Text(
                strings.accountRestrictedScope,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: AppTheme.muted,
                ),
              ),
              const SizedBox(height: 24),
              TextField(
                controller: _controller,
                minLines: 4,
                maxLines: 8,
                textInputAction: TextInputAction.newline,
                decoration: InputDecoration(
                  labelText: strings.appealMessageLabel,
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 14),
              FilledButton.icon(
                onPressed: _sending ? null : _submit,
                icon: _sending
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.send_outlined),
                label: Text(strings.submitAppeal),
              ),
            ] else ...[
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _sending ? null : _continueAfterWarning,
                child: Text(strings.continueAction),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _submit() async {
    final text = _controller.text.trim();
    if (text.isEmpty) {
      return;
    }
    setState(() {
      _sending = true;
    });
    try {
      await widget.facade.submitModerationAppeal(text);
      if (!mounted) {
        return;
      }
      _controller.clear();
      await widget.onAppealSubmitted();
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.strings.appealSent)));
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.strings.appealFailed(error))),
      );
    } finally {
      if (mounted) {
        setState(() {
          _sending = false;
        });
      }
    }
  }

  Future<void> _continueAfterWarning() async {
    setState(() {
      _sending = true;
    });
    try {
      await widget.onWarningContinued();
    } finally {
      if (mounted) {
        setState(() {
          _sending = false;
        });
      }
    }
  }
}
