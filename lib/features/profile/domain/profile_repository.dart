import '../../../core/utils/result.dart';
import 'teacher_profile.dart';

/// Access to the device owner's profile and the first-run completion flag.
abstract interface class ProfileRepository {
  /// `null` until setup has been completed.
  TeacherProfile? profile();

  bool get isOnboardingCompleted;

  Future<Result<TeacherProfile>> saveProfile({
    required String fullName,
    String staffId,
    String schoolName,
    String classTeacherOf,
  });

  Future<Result<void>> setOnboardingCompleted({required bool value});

  /// Wipes the profile and the completion flag, so setup runs again.
  Future<Result<void>> reset();

  Stream<void> watchChanges();
}
