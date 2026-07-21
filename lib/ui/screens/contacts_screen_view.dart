import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../localization/app_strings.dart';
import 'contacts_screen_styles.dart';

class ContactsEmptyState extends StatelessWidget {
  const ContactsEmptyState({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final strings = context.strings;
    return Center(
      child: Padding(
        padding: ContactsScreenStyles.emptyOuterPadding,
        child: Container(
          padding: ContactsScreenStyles.emptyInnerPadding,
          decoration: BoxDecoration(
            color: AppTheme.paper,
            borderRadius: BorderRadius.circular(
              ContactsScreenStyles.emptyCardRadius,
            ),
            border: Border.all(color: AppTheme.stroke),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: ContactsScreenStyles.emptyIconBoxSize,
                height: ContactsScreenStyles.emptyIconBoxSize,
                decoration: BoxDecoration(
                  color: AppTheme.pineSoft,
                  borderRadius: BorderRadius.circular(
                    ContactsScreenStyles.emptyIconBoxRadius,
                  ),
                ),
                child: const Icon(
                  Icons.people_alt_rounded,
                  size: ContactsScreenStyles.iconSize,
                ),
              ),
              const SizedBox(height: ContactsScreenStyles.titleSpacing),
              Text(
                strings.contactsEmptyTitle,
                style: theme.textTheme.titleLarge,
              ),
              const SizedBox(height: ContactsScreenStyles.subtitleSpacing),
              Text(
                strings.contactsEmptySubtitle,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: AppTheme.muted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
