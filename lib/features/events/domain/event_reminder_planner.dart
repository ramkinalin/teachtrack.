import '../../../core/utils/day_time.dart';
import 'entities/school_event.dart';

/// One notification to be shown at one moment.
class ScheduledReminder {
  const ScheduledReminder({
    required this.id,
    required this.when,
    required this.title,
    required this.body,
    required this.payload,
  });

  /// Android needs an int id. Derived, not stored — see
  /// [EventReminderPlanner.reminderId].
  final int id;

  final DateTime when;
  final String title;
  final String body;

  /// `event:<eventId>:<leadMinutes>`. Carried so pending notifications can be
  /// matched back to their event without keeping a side table of ids.
  final String payload;

  @override
  bool operator ==(Object other) =>
      other is ScheduledReminder &&
      other.id == id &&
      other.when == when &&
      other.title == title &&
      other.body == body &&
      other.payload == payload;

  @override
  int get hashCode => Object.hash(id, when, title, body, payload);

  @override
  String toString() => 'ScheduledReminder($id, $when, $title)';
}

/// Turns events into the exact set of notifications that should be pending.
///
/// Pure: no plugin, no `DateTime.now()`, no Flutter. All the decisions worth
/// getting right — which reminders are still in the future, what the text says,
/// which id belongs to which reminder — are testable without a device.
abstract final class EventReminderPlanner {
  static const String payloadPrefix = 'event';

  /// Reminders that should be pending for [events] at [now], soonest first.
  ///
  /// Past reminders are dropped rather than fired late: a notification for a
  /// match that finished yesterday is noise, and Android would deliver it
  /// immediately on scheduling.
  static List<ScheduledReminder> plan(
    List<SchoolEvent> events,
    DateTime now,
  ) {
    final List<ScheduledReminder> reminders = <ScheduledReminder>[];

    for (final SchoolEvent event in events) {
      final List<DateTime> times = event.reminderTimes();

      for (int i = 0; i < times.length; i++) {
        final DateTime when = times[i];
        if (!when.isAfter(now)) continue;

        final int lead = event.reminderLeadMinutes[i];
        reminders.add(
          ScheduledReminder(
            id: reminderId(event.id, lead),
            when: when,
            title: event.title,
            body: _body(event, lead),
            payload: payloadFor(event.id, lead),
          ),
        );
      }
    }

    reminders.sort(
      (ScheduledReminder a, ScheduledReminder b) => a.when.compareTo(b.when),
    );
    return reminders;
  }

  static String payloadFor(String eventId, int leadMinutes) =>
      '$payloadPrefix:$eventId:$leadMinutes';

  /// Extracts the event id from a payload, or `null` if it isn't ours.
  static String? eventIdFromPayload(String? payload) {
    if (payload == null) return null;
    final List<String> parts = payload.split(':');
    if (parts.length != 3 || parts.first != payloadPrefix) return null;
    return parts[1];
  }

  /// Stable non-negative int id for a reminder.
  ///
  /// Derived from the event id and lead rather than allocated and stored, so
  /// rescheduling produces the same ids and no bookkeeping can drift out of sync.
  /// Masked to 31 bits because Android ids must be positive ints.
  ///
  /// Hand-rolled FNV-1a rather than `Object.hash`, which is seeded from
  /// `identityHashCode` and is explicitly *not* stable between runs of the
  /// program. An id that changed after a restart would make [cancel] on a
  /// specific reminder silently no-op.
  ///
  /// Two different reminders could in principle collide, at odds of roughly one
  /// in two billion per pair. With a few hundred reminders that is negligible,
  /// and the consequence would be one missed notification rather than wrong data
  /// — an acceptable trade for having no id table to keep consistent.
  static int reminderId(String eventId, int leadMinutes) {
    const int fnvPrime = 0x01000193;
    const int mask32 = 0xFFFFFFFF;

    int hash = 0x811c9dc5;
    for (final int unit in '$eventId:$leadMinutes'.codeUnits) {
      hash = ((hash ^ unit) * fnvPrime) & mask32;
    }
    return hash & 0x7fffffff;
  }

  /// "Tomorrow", "In 2 hours", "Starting now" — how the reminder introduces
  /// itself, derived from the lead rather than the absolute time.
  static String describeLead(int leadMinutes) {
    if (leadMinutes <= 0) return 'Starting now';
    if (leadMinutes < 60) return 'In $leadMinutes minutes';
    if (leadMinutes == 60) return 'In 1 hour';
    if (leadMinutes < 1440) {
      final int hours = leadMinutes ~/ 60;
      final int minutes = leadMinutes % 60;
      return minutes == 0 ? 'In $hours hours' : 'In $hours h $minutes m';
    }
    if (leadMinutes == 1440) return 'Tomorrow';
    final int days = leadMinutes ~/ 1440;
    return 'In $days days';
  }

  static String _body(SchoolEvent event, int leadMinutes) {
    final String subtitle = event.subtitle;
    final String when = event.isAllDay
        ? describeLead(leadMinutes)
        : '${describeLead(leadMinutes)} · ${DayTime.format(event.startMinute!)}';

    return <String>[
      event.category.label,
      when,
      if (subtitle.isNotEmpty) subtitle,
    ].join(' · ');
  }
}
