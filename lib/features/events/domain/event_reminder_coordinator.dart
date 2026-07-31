import '../../../core/services/notifications/notification_service.dart';
import '../../../core/utils/clock.dart';
import 'event_reminder_planner.dart';
import 'repositories/event_repository.dart';

/// Keeps the phone's pending notifications matching the stored events.
///
/// Reconciles rather than tracking deltas: it cancels everything the app owns and
/// reschedules from the current plan. That costs a handful of platform calls and
/// buys correctness — it recovers by itself after a reboot, a restore, an edit,
/// or a reminder that simply drifted out of sync, none of which delta-tracking
/// would survive without careful bookkeeping.
class EventReminderCoordinator {
  EventReminderCoordinator({
    required EventRepository repository,
    required NotificationService notifications,
    Clock clock = const Clock(),
  })  : _repository = repository,
        _notifications = notifications,
        _clock = clock;

  final EventRepository _repository;
  final NotificationService _notifications;
  final Clock _clock;

  Future<int?>? _inFlight;

  /// Rebuilds the full set of pending reminders.
  ///
  /// Returns how many are now scheduled, or `null` **only** when notifications
  /// are not permitted — so a caller can explain why nothing will arrive rather
  /// than leaving the bell icon looking like a promise.
  ///
  /// Overlapping calls are queued behind each other rather than dropped. An
  /// earlier version returned `null` when busy, which callers could not tell
  /// apart from a refused permission: saving an event raced the background
  /// reconcile and reported a permission problem that did not exist, while never
  /// showing the prompt.
  Future<int?> sync({bool requestPermission = false}) {
    final Future<int?>? running = _inFlight;

    if (running != null) {
      return _inFlight = running.then(
        (_) => _run(requestPermission: requestPermission),
      );
    }

    final Future<int?> next = _run(requestPermission: requestPermission);
    _inFlight = next;
    return next.whenComplete(() {
      if (_inFlight == next) _inFlight = null;
    });
  }

  Future<int?> _run({required bool requestPermission}) async {
    await _notifications.init();

    if (requestPermission) {
      final bool granted = await _notifications.ensurePermission();
      if (!granted) return null;
    }

    final DateTime now = _clock.now();
    final List<ScheduledReminder> plan = EventReminderPlanner.plan(
      // Only future events can have future reminders, and the window bounds the
      // number of alarms held on the device.
      _repository.upcoming(from: now, days: 120),
      now,
    );

    await _notifications
        .cancelWithPrefix('${EventReminderPlanner.payloadPrefix}:');

    for (final ScheduledReminder reminder in plan) {
      await _notifications.schedule(
        id: reminder.id,
        when: reminder.when,
        title: reminder.title,
        body: reminder.body,
        payload: reminder.payload,
      );
    }

    return plan.length;
  }

  /// Drops every reminder this app owns, leaving other apps' alone.
  Future<void> cancelAll() async {
    // Needed before reading the pending list, which is how the app's own
    // reminders are identified.
    await _notifications.init();
    await _notifications
        .cancelWithPrefix('${EventReminderPlanner.payloadPrefix}:');
  }
}
