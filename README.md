# TeachTrack

Offline-first Android app for school teachers: today's timetable, one-tap class
completion, and a timetable editor. Built with Flutter, Riverpod and Hive.

Teachers move through Wi-Fi dead zones — classrooms, playgrounds, sports fields —
so the app reads from local storage first, queues every write, and syncs in the
background whenever a connection appears. Nothing in the UI ever waits on the
network.

See [ARCHITECTURE.md](ARCHITECTURE.md) for the design and the reasoning behind it.

## Status

| Module | State |
| --- | --- |
| Offline foundation (storage, connectivity, outbox, sync engine) | Done |
| Timetable — today view, class completion, editor | Done |
| Firebase (Auth, Firestore, Messaging) | Deliberately deferred |
| PE module — rosters, equipment checkout | Not started |

Sync currently drains through no-op handlers, so the full offline pipeline runs
end to end without a backend. Wiring Firebase means implementing
`RemoteSyncHandler` per entity type; nothing else has to change.

## CI

Every push runs `flutter analyze`, `flutter test`, and builds a debug APK, which
is attached to the workflow run as an artifact named `teachtrack-debug-apk`.

The `android/` folder is not in version control — CI scaffolds it with
`flutter create` on each run. Once Android config needs customising (permissions,
app icon, signing, `google-services.json`), remove `/android/` from `.gitignore`
and commit the folder.

## Running locally

```bash
flutter create --org com.teachtrack --project-name teachtrack /tmp/scaffold
cp -r /tmp/scaffold/android ./android   # or copy manually on Windows
flutter pub get
flutter analyze
flutter test
flutter run
```

Do not run `flutter create` directly inside this directory — it overwrites
`lib/main.dart` and `pubspec.yaml`.

Debug builds seed a sample week of classes so the app is usable immediately.
Release builds seed only the bell schedule.
