import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/sync_status_banner.dart';
import '../../../../shared/models/pending_operation.dart';
import '../../../../shared/models/sync_state.dart';
import '../../../../shared/providers/core_providers.dart';
import '../../../../shared/providers/sync_providers.dart';

/// Debug-only view of the outbox and sync engine.
///
/// Kept in the app because "did that completion actually sync?" is the question
/// most likely to come up when testing on a real device with patchy signal.
class SyncDiagnosticsScreen extends ConsumerWidget {
  const SyncDiagnosticsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final SyncState? sync = ref.watch(syncStateProvider).valueOrNull;
    final List<PendingOperation> deadLettered =
        ref.watch(deadLetteredOperationsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Sync diagnostics'),
        actions: <Widget>[
          IconButton(
            tooltip: 'Sync now',
            onPressed: () => ref.read(syncEngineProvider).drain(),
            icon: const Icon(Icons.sync_rounded),
          ),
        ],
      ),
      body: Column(
        children: <Widget>[
          const SyncStatusBanner(),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(AppSpacing.md),
              children: <Widget>[
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        _StatRow(
                          label: 'Status',
                          value: sync?.status.name ?? 'starting…',
                        ),
                        _StatRow(
                          label: 'Queued changes',
                          value: '${sync?.pendingCount ?? 0}',
                        ),
                        _StatRow(
                          label: 'Needs attention',
                          value: '${sync?.deadLetteredCount ?? 0}',
                        ),
                        _StatRow(
                          label: 'Last synced',
                          value: sync?.lastSuccessfulSyncAt
                                  ?.toLocal()
                                  .toString()
                                  .split('.')
                                  .first ??
                              'never',
                        ),
                        if (sync?.lastError != null)
                          _StatRow(
                            label: 'Last error',
                            value: sync!.lastError!,
                          ),
                      ],
                    ),
                  ),
                ),
                if (deadLettered.isNotEmpty) ...<Widget>[
                  const SizedBox(height: AppSpacing.lg),
                  Text(
                    'Needs attention',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  for (final PendingOperation op in deadLettered)
                    Card(
                      child: ListTile(
                        title: Text('${op.entityType} · ${op.operation.name}'),
                        subtitle: Text(
                          '${op.attemptCount} attempts\n${op.lastError ?? ''}',
                        ),
                        isThreeLine: true,
                        trailing: IconButton(
                          tooltip: 'Retry',
                          icon: const Icon(Icons.refresh_rounded),
                          onPressed: () =>
                              ref.read(syncEngineProvider).retryDeadLettered(op),
                        ),
                      ),
                    ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatRow extends StatelessWidget {
  const _StatRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: <Widget>[
          Text(
            label,
            style: text.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}
