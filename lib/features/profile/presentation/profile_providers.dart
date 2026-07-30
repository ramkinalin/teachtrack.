import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/providers/core_providers.dart';
import '../data/profile_repository_impl.dart';
import '../domain/profile_repository.dart';
import '../domain/teacher_profile.dart';

final profileRepositoryProvider = Provider<ProfileRepository>((ref) {
  return ProfileRepositoryImpl(
    settingsBox: ref.watch(localStorageServiceProvider).settingsBox,
    syncQueue: ref.watch(syncQueueServiceProvider),
  );
});

/// Snapshot of profile plus setup state, read synchronously from the settings box
/// and refreshed whenever either value changes.
class ProfileState {
  const ProfileState({required this.profile, required this.onboardingCompleted});

  final TeacherProfile? profile;
  final bool onboardingCompleted;

  bool get needsSetup => !onboardingCompleted;

  String get greetingName {
    final String? name = profile?.fullName.trim();
    if (name == null || name.isEmpty) return 'there';
    // First word only: "Good morning, Narayanan" reads better than the full name.
    return name.split(RegExp(r'\s+')).first;
  }

  @override
  bool operator ==(Object other) =>
      other is ProfileState &&
      other.profile == profile &&
      other.onboardingCompleted == onboardingCompleted;

  @override
  int get hashCode => Object.hash(profile, onboardingCompleted);
}

class ProfileNotifier extends Notifier<ProfileState> {
  @override
  ProfileState build() {
    final ProfileRepository repository = ref.watch(profileRepositoryProvider);

    final StreamSubscription<void> subscription =
        repository.watchChanges().listen((void _) {
      state = _read(repository);
    });
    ref.onDispose(subscription.cancel);

    return _read(repository);
  }

  ProfileState _read(ProfileRepository repository) => ProfileState(
        profile: repository.profile(),
        onboardingCompleted: repository.isOnboardingCompleted,
      );
}

final profileProvider =
    NotifierProvider<ProfileNotifier, ProfileState>(ProfileNotifier.new);

/// The id stamped onto timetable entries. Empty until setup completes.
final activeTeacherIdProvider = Provider<String>((ref) {
  return ref.watch(profileProvider).profile?.id ?? '';
});
