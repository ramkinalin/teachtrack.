import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

/// Schedules and cancels local notifications.
///
/// Local means the phone's own alarm system: no server, no push, works with the
/// device in a drawer and no signal. The interface exists so the reminder logic
/// can be exercised in tests against [FakeNotificationService] rather than a
/// plugin that needs a real device.
abstract interface class NotificationService {
  /// Must be awaited before scheduling. Safe to call more than once, and safe to
  /// call concurrently.
  Future<void> init();

  /// Payloads of notifications the user tapped, so the app can open the thing
  /// being reminded about rather than wherever it was last left.
  Stream<String> get tappedPayloads;

  /// Asks for the Android 13+ notification permission, returning whether it is
  /// granted. Called at the point a reminder is actually wanted, not at launch —
  /// a permission prompt on first open, before the app has explained itself, is
  /// the fastest way to get denied.
  Future<bool> ensurePermission();

  Future<void> schedule({
    required int id,
    required DateTime when,
    required String title,
    required String body,
    required String payload,
  });

  Future<void> cancel(int id);

  /// Cancels every notification this app scheduled whose payload starts with
  /// [payloadPrefix].
  Future<void> cancelWithPrefix(String payloadPrefix);

  Future<List<PendingNotificationRequest>> pending();
}

class LocalNotificationService implements NotificationService {
  LocalNotificationService({FlutterLocalNotificationsPlugin? plugin})
      : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;

  final StreamController<String> _taps = StreamController<String>.broadcast();

  /// Memoises the *future*, not a bool. Two callers — the reminder coordinator
  /// and the pending-count provider — can arrive at once, and a flag set after
  /// the awaits would let both run initialisation, briefly leaving `tz.local` as
  /// UTC while a schedule call was in flight.
  Future<void>? _initialising;

  static const AndroidNotificationDetails _androidDetails =
      AndroidNotificationDetails(
    'teachtrack_reminders',
    'Reminders',
    channelDescription: 'Class tests, matches, tournaments and duties',
    importance: Importance.high,
    priority: Priority.high,
  );

  @override
  Stream<String> get tappedPayloads => _taps.stream;

  @override
  Future<void> init() => _initialising ??= _doInit();

  Future<void> _doInit() async {
    tz_data.initializeTimeZones();
    // The device's own zone, so a reminder set for 08:00 arrives at 08:00 local
    // rather than in UTC.
    try {
      final String name = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(name));
    } on Object catch (error) {
      // An unrecognised zone name must not stop the app booting; UTC is wrong
      // but harmless compared to a crash on launch.
      debugPrint('TeachTrack: could not resolve local timezone ($error)');
    }

    await _plugin.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        final String? payload = response.payload;
        if (payload != null && payload.isNotEmpty && !_taps.isClosed) {
          _taps.add(payload);
        }
      },
    );
  }

  Future<void> dispose() => _taps.close();

  @override
  Future<bool> ensurePermission() async {
    final AndroidFlutterLocalNotificationsPlugin? android =
        _plugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    if (android == null) return false;

    // Returns null on Android 12 and below, where the permission does not exist
    // and notifications are allowed by default.
    return await android.requestNotificationsPermission() ?? true;
  }

  @override
  Future<void> schedule({
    required int id,
    required DateTime when,
    required String title,
    required String body,
    required String payload,
  }) async {
    await init();

    await _plugin.zonedSchedule(
      id,
      title,
      body,
      tz.TZDateTime.from(when, tz.local),
      const NotificationDetails(android: _androidDetails),
      payload: payload,
      // Inexact on purpose. Exact alarms need SCHEDULE_EXACT_ALARM, which Google
      // restricts to alarm and calendar apps and which risks a Play Store
      // rejection. The cost is a minute or two of lateness.
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
    );
  }

  @override
  Future<void> cancel(int id) => _plugin.cancel(id);

  @override
  Future<void> cancelWithPrefix(String payloadPrefix) async {
    for (final PendingNotificationRequest request in await pending()) {
      if (request.payload?.startsWith(payloadPrefix) ?? false) {
        await _plugin.cancel(request.id);
      }
    }
  }

  @override
  Future<List<PendingNotificationRequest>> pending() =>
      _plugin.pendingNotificationRequests();
}

/// Records calls instead of touching the platform, so reminder reconciliation
/// can be tested.
class FakeNotificationService implements NotificationService {
  FakeNotificationService({this.permissionGranted = true});

  bool permissionGranted;
  int initCalls = 0;
  int permissionRequests = 0;

  final Map<int, PendingNotificationRequest> scheduled =
      <int, PendingNotificationRequest>{};
  final List<int> cancelled = <int>[];

  final StreamController<String> taps = StreamController<String>.broadcast();

  @override
  Stream<String> get tappedPayloads => taps.stream;

  @override
  Future<void> init() async => initCalls++;

  @override
  Future<bool> ensurePermission() async {
    permissionRequests++;
    return permissionGranted;
  }

  @override
  Future<void> schedule({
    required int id,
    required DateTime when,
    required String title,
    required String body,
    required String payload,
  }) async {
    scheduled[id] = PendingNotificationRequest(id, title, body, payload);
  }

  @override
  Future<void> cancel(int id) async {
    cancelled.add(id);
    scheduled.remove(id);
  }

  @override
  Future<void> cancelWithPrefix(String payloadPrefix) async {
    final List<int> matching = scheduled.values
        .where((PendingNotificationRequest r) =>
            r.payload?.startsWith(payloadPrefix) ?? false)
        .map((PendingNotificationRequest r) => r.id)
        .toList(growable: false);

    for (final int id in matching) {
      await cancel(id);
    }
  }

  @override
  Future<List<PendingNotificationRequest>> pending() async =>
      scheduled.values.toList(growable: false);

  Future<void> dispose() => taps.close();
}
