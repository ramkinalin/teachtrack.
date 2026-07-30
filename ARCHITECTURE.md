# TeachTrack — Architecture

Offline-first Android app for school teachers. Flutter + Riverpod + Hive, with
Firebase (Spark plan) as a secondary, best-effort sync target.

## Layering

```
presentation (widgets, screens)      features/<module>/presentation
        ↓ watches providers
state            (Riverpod)          features/<module>/presentation/providers
        ↓ calls
domain / repository                  features/<module>/domain, shared/repositories
        ↓ reads local first, queues writes
local data source (Hive)             core/services/local_storage_service.dart
remote data source (Firestore)       features/<module>/data/remote  ← added later
```

Widgets hold no business logic. Repositories return `Result<T>` rather than
throwing, so failure paths are part of every signature.

## The write path

Every mutation is local-then-queued. Nothing in the UI awaits the network.

1. Repository writes the new state to its Hive box (synchronous, instant).
2. Repository appends a `PendingOperation` to the outbox via `SyncQueueService`.
3. UI rebuilds from local state and the interaction is finished.
4. `SyncEngine` drains the outbox in the background when it can.

`entityId` is generated client-side (UUID v4) so a record created on a sports
field keeps the same identity once it reaches Firestore.

## Outbox and Firestore economics

`SyncQueueService` **coalesces** operations per entity instead of stacking them:
five taps on the same class produce one remote write, not five. Creates followed
by deletes are dropped entirely, since nothing ever reached the server.
`SyncEngine` groups due operations by entity type and hands each group to its
handler as one batch, which maps directly onto a Firestore `WriteBatch`.

Failures use exponential back-off (5s → 30min cap, 8 attempts) and then
dead-letter. Dead-lettered operations stop retrying, stop consuming quota, and
surface in the UI for the teacher to retry or discard.

While a batch is in flight its operation ids are hidden from both coalescing and
re-dispatch. A remote call takes hundreds of milliseconds and the UI keeps
writing throughout; without this, an edit made mid-flight would coalesce into an
operation that is about to be deleted on success, and would silently never sync.

## Sync handler registration

`core` has no Firebase dependency. Each feature implements `RemoteSyncHandler`
for its own entity type and registers it by overriding
`remoteSyncHandlersProvider`. Handlers **must be idempotent** — a batch can be
applied twice if the response is lost after the server commits.

Until a Firebase project exists, `NoopSyncHandler` stands in so the full
pipeline runs end to end.

## Timetable module

Periods live in their own box and own all times. A `TimetableEntry` stores only
`weekday + periodId + subject + classGroup + room`, so a bell-time change is one
edit and every entry stays small. Slot identity is `(weekday, periodId)`, which
is the rule `validateEntry` enforces — and it validates against the teaching week
the editor can actually display, so nothing can be saved that the UI cannot show.

`ClassSession` records what happened to one entry on one date, and is written
**only when a teacher acts**. No record means scheduled. A normal week therefore
costs zero writes. Session ids are deterministic (`2026-07-30_entry-abc`), so a
completion recorded offline maps to exactly one Firestore document and replaying
the write is harmless.

`ScheduleResolver` is pure: it takes a day's schedule and an instant and returns
current class, next class and countdowns. No `DateTime.now()`, no Riverpod, no
Flutter — which is why the awkward cases (the exact minute a period ends, gaps
between periods, end of day) are unit-tested rather than eyeballed.

Reads are synchronous all the way from Hive to the widget, so screens paint real
content on the first frame instead of a spinner. The one-second countdown ticker
is `autoDispose` and deliberately watched only by the hero card; the day list
watches a `select`-narrowed slice so it does not rebuild every second.
`selectedDateProvider` self-invalidates just after midnight — otherwise an app
left open overnight would file completions under yesterday.

## Hive type ids

Ids in `core/constants/hive_boxes.dart` are permanent. Once a build ships,
renumbering them corrupts local data on existing installs. Core reserves 1–9;
feature models start at 10. Adapters are hand-written to avoid `build_runner`.

## Deliberately deferred

Firebase packages are **not** in `pubspec.yaml` yet: adding `firebase_core`
pulls in the Gradle Google Services plugin, which fails the build without a
`google-services.json`. The remote layer is defined behind interfaces so
Firebase can be dropped in without touching the engine.

Authentication is likewise deferred. Firebase Auth email/password is free and
unmetered on Spark and remains the plan; the seam is `AuthFailure` plus a future
`AuthRepository`.

## Testing

Time and connectivity are injected (`FakeClock`, `FakeConnectivityService`) so
back-off, retry and dead-lettering are tested without sleeping.

```
flutter analyze
flutter test
```
