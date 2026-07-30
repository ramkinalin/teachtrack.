/// Domain-level error type.
///
/// Repositories translate exceptions into [Failure] values so that the
/// presentation layer never has to reason about storage or transport details.
sealed class Failure {
  const Failure(this.message, {this.cause});

  final String message;
  final Object? cause;

  @override
  String toString() => '$runtimeType: $message';
}

/// Local storage (Hive / SQLite) could not complete an operation.
final class CacheFailure extends Failure {
  const CacheFailure(super.message, {super.cause});
}

/// A remote call failed. Never surfaced as a blocking error in offline-first
/// flows — the write stays queued and is retried later.
final class RemoteFailure extends Failure {
  const RemoteFailure(super.message, {super.cause});
}

/// The device has no usable connection.
final class NetworkFailure extends Failure {
  // Explicit superinitializer rather than super-parameters: the base takes
  // `message` positionally, which cannot be forwarded from a named parameter.
  const NetworkFailure({
    String message = 'No internet connection',
    Object? cause,
  }) : super(message, cause: cause);
}

/// Input or state did not satisfy a business rule.
final class ValidationFailure extends Failure {
  const ValidationFailure(super.message, {this.field, super.cause});

  final String? field;
}

/// The user is not signed in, or the session expired.
final class AuthFailure extends Failure {
  const AuthFailure(super.message, {super.cause});
}

/// Fallback for genuinely unexpected errors.
final class UnexpectedFailure extends Failure {
  const UnexpectedFailure(super.message, {super.cause});
}
