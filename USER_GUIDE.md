# TeachTrack — User Guide

A guide to using the app as it stands today. Written for a teacher picking it up
for the first time.

---

## 1. First launch: setup

The first time you open TeachTrack it walks you through four screens. There's a
**Skip** button in the top right if you'd rather explore first — you can run setup
again later from Settings.

**Step 1 — Welcome.** Explains what the app does. Read it and tap **Next**.

**Step 2 — Who are you?** Enter your name. School and Staff ID are optional. If
you're a class teacher, turn on **I am a class teacher** and type your section
(for example `8B`). Tap **Next** — this saves your details before moving on, so if
the name field is empty it will stop you here.

**Step 3 — When does your school day start?** The app assumes a standard eight-period
day running 08:00 to 15:00, with a break at 09:30 and lunch at 11:15. Tap the
**First period starts at** button and pick your school's real start time. Every
period, break and gap shifts by the same amount, so the shape of your day is
preserved and you only answer one question. The list below the button updates so
you can check it. Tap **Next**.

**Step 4 — Add your timetable.** Tap **Add a class** to enter your first one. The
form that opens is the same one you'll use from now on, so this is worth doing
once here rather than skipping. Add as many as you like, then tap
**Start using TeachTrack**.

---

## 2. Entering your timetable

Tap the **calendar icon** in the top right of the home screen. You'll see a tab
for each day, Monday to Saturday, opening on today.

**Step 1 —** Pick the day tab you want to fill in.

**Step 2 —** Tap **Add class**.

**Step 3 —** Fill in the form:

- **Day** — pre-filled with the tab you were on; change it here if you'd rather.
- **Period** — the dropdown shows your periods with their times. Breaks and lunch
  aren't listed, since you don't teach through them.
- **Subject** — pick from the dropdown. If your subject isn't there, choose
  **+ Add new subject…**, type it, and it's saved to your list for next time.
- **Class** — the section you teach in that period, for example `8B`.
- **Room or location** — optional. Useful for `Main Field` or `Lab 2`.
- **Physical education** — turn this on for PE and games lessons. It marks the
  class with a small ball icon and will switch on the PE tools when that module
  arrives.

**Step 4 —** Tap **Add**.

**A note on conflicts.** You can only have one class per period per day. If you
pick a period that's already taken, the form refuses and tells you which class is
already there. That's a guard against double-booking yourself, not a bug.

**To edit a class,** tap its row. **To delete one,** tap the bin icon and confirm.

Your timetable repeats every week — you enter it once.

---

## 3. Using it day to day

The home screen shows today. The heading is the day of the week with your name
beneath it.

**The card at the top** is the important part. During a lesson it turns green and
shows the subject, the class, the room, and how much time is left, counting down
live. Between lessons it goes grey and shows what's next and how long until it
starts. After your last lesson it says the day is over.

**To mark a class done,** either tap **Class completed** on the green card, or tap
the circle on the right of any row in the list. It fills in immediately and a
short **Undo** appears at the bottom if you tapped the wrong one.

**For anything other than "done",** tap the **⋮** menu on a row. You can mark a
class **cancelled** — useful for an assembly or a holiday — or **clear** it back
to nothing.

**Breaks and lunch** appear in the list in italics with no controls, so you can see
the shape of your day without being asked to tick them off.

**At the end of the day,** if lessons finished without being marked, a card appears
at the bottom of the list offering **Mark all completed**. Ignoring it is fine —
it's a reminder, not a demand.

---

## 4. Working without internet

This is the point of the app. Everything above works with no signal at all:
classrooms, playgrounds, sports fields, dead zones.

When you're offline a grey bar appears below the heading telling you so, and how
many changes are waiting on your device. Nothing is lost and nothing is blocked —
you never wait for the network to finish a tap.

**Being honest about the current state:** there is no cloud backend connected yet.
Your data lives on this phone only. The syncing machinery is built and running,
but it's wired to a placeholder, so nothing actually leaves the device. Until
Firebase is connected, treat this phone as the only copy — and don't clear the
app's data expecting a backup.

---

## 5. Settings

Tap the **gear icon** in the top right of the home screen.

- **Your name** — tap to edit your details at any time.
- **Edit timetable** — same screen as the calendar icon.
- **Subjects** — add or remove subjects from the dropdown. Removing one here does
  **not** change classes you've already added; the list only controls what you're
  offered next time. You can't delete the last remaining subject, and the restore
  icon in the top right puts the standard list back.
- **Sync diagnostics** — what's queued and whether anything failed. Mostly useful
  for testing on a patchy connection.
- **Load sample timetable** — fills in a demo week so you can try the app without
  entering your own. Safe to tap; it skips anything that would clash.
- **Run setup again** — replays the four introduction screens.
- **Clear all data** — removes your timetable and every marked class. Your profile,
  school timings and subject list survive. This cannot be undone.

---

## 6. Not there yet

So you know what to expect:

- No login, and no cloud backup — one teacher, one phone.
- No headmaster or admin view of who teaches which class. The data model is ready
  for it; the screens aren't built.
- No PE tools yet. Marking a class as physical education today only tags it.
- No attendance, homework, leave or reports.
- Sunday isn't available. The week runs Monday to Saturday.
