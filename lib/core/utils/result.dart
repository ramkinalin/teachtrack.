import '../errors/failures.dart';

/// Explicit success/failure wrapper.
///
/// Preferred over throwing across layer boundaries: it makes failure paths part
/// of the signature and forces callers to handle them, which matters most for
/// sync code that must degrade rather than crash.
sealed class Result<T> {
  const Result();

  bool get isOk => this is Ok<T>;
  bool get isErr => this is Err<T>;

  /// The value on success, otherwise `null`.
  T? get valueOrNull => switch (this) {
        Ok<T>(:final value) => value,
        Err<T>() => null,
      };

  /// The failure on error, otherwise `null`.
  Failure? get failureOrNull => switch (this) {
        Ok<T>() => null,
        Err<T>(:final failure) => failure,
      };

  R fold<R>(R Function(T value) onOk, R Function(Failure failure) onErr) =>
      switch (this) {
        Ok<T>(:final value) => onOk(value),
        Err<T>(:final failure) => onErr(failure),
      };

  Result<R> map<R>(R Function(T value) transform) => switch (this) {
        Ok<T>(:final value) => Ok<R>(transform(value)),
        Err<T>(:final failure) => Err<R>(failure),
      };
}

final class Ok<T> extends Result<T> {
  const Ok(this.value);

  final T value;
}

final class Err<T> extends Result<T> {
  const Err(this.failure);

  final Failure failure;
}

/// Convenience for `Result<void>`-style returns.
const Result<void> okVoid = Ok<void>(null);
