import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';

/// Reports whether the device has a network interface available.
///
/// Deliberately narrow: it answers "is there an interface?", not "is Firestore
/// reachable?". Reachability is proven by the sync engine actually succeeding,
/// which avoids burning quota on probe requests.
abstract interface class ConnectivityService {
  /// Best-known current value, available synchronously after the first event.
  bool get isOnline;

  /// Emits on every transition. Broadcast, so multiple listeners are safe.
  Stream<bool> get onStatusChanged;

  Future<bool> checkNow();

  Future<void> dispose();
}

class ConnectivityPlusService implements ConnectivityService {
  ConnectivityPlusService({Connectivity? connectivity})
      : _connectivity = connectivity ?? Connectivity() {
    _subscription = _connectivity.onConnectivityChanged.listen(
      (List<ConnectivityResult> results) => _emit(_hasInterface(results)),
      onError: (Object _) => _emit(false),
    );
    // Seed the initial value without blocking construction.
    unawaited(checkNow());
  }

  final Connectivity _connectivity;
  final StreamController<bool> _controller = StreamController<bool>.broadcast();
  StreamSubscription<List<ConnectivityResult>>? _subscription;

  bool _isOnline = false;

  @override
  bool get isOnline => _isOnline;

  @override
  Stream<bool> get onStatusChanged => _controller.stream;

  @override
  Future<bool> checkNow() async {
    try {
      final List<ConnectivityResult> results =
          await _connectivity.checkConnectivity();
      _emit(_hasInterface(results));
    } on Object {
      _emit(false);
    }
    return _isOnline;
  }

  void _emit(bool value) {
    if (value == _isOnline) return;
    _isOnline = value;
    if (!_controller.isClosed) _controller.add(value);
  }

  static bool _hasInterface(List<ConnectivityResult> results) =>
      results.any((ConnectivityResult r) => r != ConnectivityResult.none);

  @override
  Future<void> dispose() async {
    await _subscription?.cancel();
    _subscription = null;
    await _controller.close();
  }
}

/// Test double with manual control over the reported status.
class FakeConnectivityService implements ConnectivityService {
  FakeConnectivityService({bool initialOnline = true})
      : _isOnline = initialOnline;

  final StreamController<bool> _controller = StreamController<bool>.broadcast();
  bool _isOnline;

  @override
  bool get isOnline => _isOnline;

  @override
  Stream<bool> get onStatusChanged => _controller.stream;

  @override
  Future<bool> checkNow() async => _isOnline;

  void setOnline(bool value) {
    if (value == _isOnline) return;
    _isOnline = value;
    _controller.add(value);
  }

  @override
  Future<void> dispose() => _controller.close();
}
