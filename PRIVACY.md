# NextRep Privacy

_Last updated: 5 October 2026. Applies to NextRep 1.0.0 (Winter Arc)._

NextRep is a local-first app. Everything you put into it stays on your
device, in the app's own storage, unless you choose to move it. NextRep has
no servers, no accounts and no network access.

This page describes what the app actually does, as built. It is not a
substitute for the privacy policy you publish with a store listing (see
[docs/STORE_READINESS.md](docs/STORE_READINESS.md)).

## What NextRep stores, and where

All of it is kept in one SQLite database in the app's private storage on
your device:

| Data | Examples |
|---|---|
| Habits and their history | names, goals, daily progress, Minimum Days, goal changes by date |
| Arcs | Rolling or Seasonal, start, end and join dates, status |
| XP and achievements | the XP ledger and the date each achievement was unlocked |
| Journal reflections | mood, "one win", "one thing to improve", per day |
| Reminder settings | whether each reminder is on, and its time |

Streaks, levels, Perfect Days, the Journey, summaries and Insights are
worked out on the device from that data. They are not stored separately and
never leave the device.

Habit templates are part of the app. Custom habit ids are random and made on
the device.

## What NextRep does not do

- No account or sign-in.
- No network access. The Android release build doesn't request the
  `INTERNET` permission, so the app can't send anything anywhere.
- No analytics, telemetry, crash reporting, advertising, tracking or ad
  identifiers.
- No cloud sync and no NextRep servers.
- No sale or sharing of your data. NextRep never has it.
- No AI or remote processing. Insights are counts and percentages computed
  on the device. Reflection text is never read for insights.
- No health, location, contacts, camera, microphone or photo access.

Failures are recorded only through the Dart developer log. That log is
visible in debug and profile builds and does nothing in release builds.
Even there, the entries never include reflection text or backup contents.

## Backups you export

- A backup is made only when you tap **Export Backup**. You then choose
  where to save it in the system file dialog (for example Files, Drive or a
  USB drive).
- The file contains all of the data above, **including your reflections**.
- **Backup files are not encrypted by NextRep.** Anyone who can open the
  file can read it. Store it somewhere you trust. The app says this before
  every export.
- The backup includes a checksum so accidental corruption can be detected.
  The checksum is not a security feature: it doesn't make the file secure,
  private or tamper-proof.
- Restoring reads only the file you pick. It replaces the data on the device
  after you confirm twice, and reminders come back turned off.

## Your device's own backups

NextRep doesn't turn off your phone's own system backup:

- **Android:** if Backup is on in system settings, Android may include the
  app's data in the device backup to your Google account, and copy it during
  a device-to-device transfer.
- **iPhone:** iCloud Backup and computer backups include app data.

Your phone's system, not NextRep, encrypts and controls those backups. You
can turn them off in system settings.

## Notifications

- Reminders are **off by default**. The app asks for notification
  permission only when you turn a reminder on.
- They are local notifications, scheduled on your device. There is no push
  service and no Firebase.
- Notification text is generic ("Your Winter Arc is waiting.", "How did
  today go?"). It never includes your habits or reflections.
- If you turn notifications off in system settings, NextRep keeps your
  reminder setting, tells you notifications are off and doesn't ask again.

## Permissions (Android release build)

| Permission | Why |
|---|---|
| `POST_NOTIFICATIONS` | show the optional reminders (Android 13+, asked when you turn one on) |
| `VIBRATE` | notification and haptic feedback |
| `RECEIVE_BOOT_COMPLETED` | re-schedule pending reminders after a restart |
| `com.nextrep.nextrep.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION` | an app-private AndroidX permission; it grants nothing to other apps |

The app requests no storage permission: backups go through the system
document picker. It requests no exact-alarm permission: reminders may arrive
a few minutes late. `INTERNET` appears only in debug and profile builds,
which Flutter's development tools need. It is never in a release build.

On iOS the app uses only local notification permission, asked when you turn
a reminder on.

## Deleting your data

- **Delete Arc** (on a completed arc's summary) deletes that arc and
  everything in it.
- **Cancel setup** deletes an arc that hasn't started yet.
- Uninstalling the app deletes all its data from the device. Backups you
  exported, and your phone's own system backups, are not affected.

## Contact

NextRep is published by its developer. A contact address for privacy
questions is required on store listings. Add it here before release.
