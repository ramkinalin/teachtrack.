import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/models/sync_state.dart';
import '../../shared/providers/sync_providers.dart';
import '../theme/app_spacing.dart';

/// Slim, non-blocking indicator of synchronisation state.
///
/// Offline is presented as normal operation, not an error — the app is designed
/// to work this way, and teachers should never feel they must find a signal.
class SyncStatusBanner extends ConsumerWidget {
  const SyncStatusBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final SyncState? state = ref.watch(syncStateProvider).valueOrNull;
    if (state == null) return const SizedBox.shrink();

    // Nothing to report: online and fully drained.
    if (state.status == SyncStatus.synced && !state.hasUnsyncedWork) {
      return const SizedBox.shrink();
    }

    final _BannerStyle style = _BannerStyle.forState(
      state,
      Theme.of(context).colorScheme,
    );

    return Semantics(
      liveRegion: true,
      label: style.label,
      child: Container(
        width: double.infinity,
        color: style.background,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        child: Row(
          children: <Widget>[
            Icon(style.icon, size: 18, color: style.foreground),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                style.label,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: style.foreground),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Maps a [SyncState] onto presentation values, keeping the widget declarative.
class _BannerStyle {
  const _BannerStyle({
    required this.icon,
    required this.label,
    required this.background,
    required this.foreground,
  });

  factory _BannerStyle.forState(SyncState state, ColorScheme scheme) {
    switch (state.status) {
      case SyncStatus.offline:
        return _BannerStyle(
          icon: Icons.cloud_off_rounded,
          label: state.hasUnsyncedWork
              ? 'Offline · ${_changes(state.pendingCount)} saved on device'
              : 'Offline · everything still works',
          background: scheme.surfaceContainerHighest,
          foreground: scheme.onSurfaceVariant,
        );
      case SyncStatus.syncing:
        return _BannerStyle(
          icon: Icons.sync_rounded,
          label: 'Syncing…',
          background: scheme.secondaryContainer,
          foreground: scheme.onSecondaryContainer,
        );
      case SyncStatus.retrying:
        return _BannerStyle(
          icon: Icons.schedule_rounded,
          label: 'Sync will retry automatically',
          background: scheme.surfaceContainerHighest,
          foreground: scheme.onSurfaceVariant,
        );
      case SyncStatus.needsAttention:
        return _BannerStyle(
          icon: Icons.error_outline_rounded,
          label: '${_changes(state.deadLetteredCount)} need attention',
          background: scheme.errorContainer,
          foreground: scheme.onErrorContainer,
        );
      case SyncStatus.synced:
        return _BannerStyle(
          icon: Icons.cloud_upload_rounded,
          label: '${_changes(state.pendingCount)} waiting to sync',
          background: scheme.surfaceContainerHighest,
          foreground: scheme.onSurfaceVariant,
        );
    }
  }

  final IconData icon;
  final String label;
  final Color background;
  final Color foreground;

  static String _changes(int count) =>
      '$count change${count == 1 ? '' : 's'}';
}
