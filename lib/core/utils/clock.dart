/// Injectable time source.
///
/// Retry back-off, period countdowns and "is this class current?" logic all
/// depend on the current time. Injecting it keeps that logic unit-testable
/// without sleeping in tests.
class Clock {
  const Clock();

  DateTime now() => DateTime.now();
}

/// Test double: time only advances when explicitly told to.
class FakeClock implements Clock {
  FakeClock(this._now);

  DateTime _now;

  @override
  DateTime now() => _now;

  void advance(Duration duration) => _now = _now.add(duration);

  void setTo(DateTime value) => _now = value;
}
