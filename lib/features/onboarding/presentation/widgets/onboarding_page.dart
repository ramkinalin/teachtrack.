import 'package:flutter/material.dart';

import '../../../../core/theme/app_spacing.dart';

/// Shared layout for a single setup step.
///
/// One consistent shape — icon, title, one line of explanation, then content —
/// so each step feels like the same conversation rather than four screens.
class OnboardingPage extends StatelessWidget {
  const OnboardingPage({
    required this.icon,
    required this.title,
    required this.body,
    super.key,
    this.child,
  });

  final IconData icon;
  final String title;
  final String body;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final TextTheme text = Theme.of(context).textTheme;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.lg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: scheme.primaryContainer,
              borderRadius: BorderRadius.circular(AppRadius.lg),
            ),
            child: Icon(icon, size: 28, color: scheme.onPrimaryContainer),
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(title, style: text.headlineSmall),
          const SizedBox(height: AppSpacing.sm),
          Text(
            body,
            style: text.bodyLarge?.copyWith(color: scheme.onSurfaceVariant),
          ),
          if (child != null) ...<Widget>[
            const SizedBox(height: AppSpacing.xl),
            child!,
          ],
        ],
      ),
    );
  }
}
