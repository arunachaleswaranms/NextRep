# NextRep Privacy

_Last updated: 14 October 2026. Applies to NextRep 1.1.0 (Winter Arc) and
to builds of the current source, which add Hydration Coach and Focus Guard
(planned for 1.2, not yet released)._

NextRep is a local-first app. Everything you put into it stays on your
device, in the app's own storage, unless you choose to move it: by
exporting a backup, or by sharing a progress card. NextRep has no servers,
no accounts and no network access.

In short:

- **Automatic transmission: none.** NextRep never sends anything by itself.
- **Sharing you start: possible.** You can make a progress, goal or
  achievement image and hand it to another app through your phone's share
  sheet. Nothing leaves NextRep until you tap **Share** and pick an app.

This page describes what the app actually does, as built. It applies to
the official Android APKs published on this repository's GitHub Releases
page, and to builds made from this source.

## What NextRep stores, and where

All of it is kept in one SQLite database in the app's private storage on
your device:

| Data | Examples |
|---|---|
| Habits and their history | names, goals, daily progress, Minimum Days, goal changes by date |
| Arcs | Rolling or Seasonal, start, end and join dates, status |
| XP and achievements | the XP ledger and the date each achievement was unlocked |
| Journal reflections | mood, "one win", "one thing to improve", per day |
| Reminder settings | whether each reminder is on, its time, and Hydration Coach's active hours and style |
| Focus Guard settings (Android, optional) | whether it is on, the apps you chose (their package names, e.g. `com.example.app`), your daily budget, and the date of the last reminder it sent |

Streaks, levels, Perfect Days, the Journey, summaries and Insights are
worked out on the device from that data. They are not stored separately and
never leave the device.

NextRep stores **no app-usage history**: no record of how long you used
any app, on any day. See [Focus Guard](#focus-guard-android-optional).

Habit templates are part of the app. Custom habit ids are random and made on
the device.

## What NextRep does not do

- No account or sign-in.
- No network access. The Android release build doesn't request the
  `INTERNET` permission, so the app can't send anything anywhere.
- No analytics, telemetry, crash reporting, advertising, tracking or ad
  identifiers.
- No cloud sync and no NextRep servers.
- No sale or disclosure of your data. NextRep never automatically
  transmits, sells or discloses anything you put into it. The only data
  that leaves the app is what you choose to move yourself: a backup you
  export, or a share card you send (below).
- No AI or remote processing. Insights are counts and percentages computed
  on the device. Reflection text is never read for insights.
- No health, location, contacts, camera, microphone or photo access.
- No access to how you use other apps, unless you turn on Focus Guard and
  grant Android's Usage Access yourself (below). Even then NextRep never
  blocks, closes, covers or reads other apps.

Failures are recorded only through the Dart developer log. That log is
visible in debug and profile builds and does nothing in release builds.
Even there, the entries never include reflection text or backup contents.

## Share cards

From version 1.1.0 you can share a picture of your progress. There are
three cards: **Today's Progress** and **My Arc** (from Share progress on
Today), and an unlocked **achievement** (from its detail sheet).

How it works:

- The card is drawn **on your device** as a 1080 × 1350 PNG image. Nothing
  is uploaded to make it.
- A card is shared **only when you tap Share**. NextRep then opens the
  operating system's own share sheet, and you pick where it goes. NextRep
  never posts, uploads or sends anything by itself.
- The image carries only the progress, goals or achievement you chose to
  show, with a subtle NextRep name. It contains no link.
- The image may go with a short caption describing the card: for example
  your Arc and challenge day, or the achievement title. The caption contains
  no repository link, tracking parameter or referral identifier.
- NextRep keeps **no share history** and doesn't record which app you
  choose. (Android tells the share library which app was picked; NextRep
  only looks at whether the sheet was used or closed, and keeps nothing.)
- NextRep doesn't read your contacts or social accounts, and doesn't know
  who you send a card to.
- The image is written to NextRep's **private cache** only for as long as
  the share takes, and NextRep deletes its copy when the sheet closes.
  Android's share library may keep its own copy in the app's private cache
  until the next share or until the system clears the cache. NextRep never
  saves cards to your Photos, Gallery or Downloads, and it needs no storage,
  media, photo or contacts permission to share.
- Sharing doesn't change your data and earns no XP.

On **Today's Progress** you can hide habit names, your XP and level, and
your streak before you share. Hidden values are not in the image at all.
Today's Progress shows Sleep Before as done or not done, without a time.

**My Arc** shows your habits with their full daily goals. For a "before a
time" habit, the goal is its target time (for example "Before 23:30"). It
never shows a time you logged.

A share card **never** contains:

- your Journal reflections (win, thing to improve) or moods
- backup contents
- reminder settings
- logged clock times, such as your exact Sleep Before bedtime
- calendar dates (cards use the Arc day number)
- device identifiers, or anything about how the app is signed

**Once you share a card, the app you picked has it.** WhatsApp, Instagram,
email, a messaging app or a cloud drive each have their own privacy
practices, which NextRep doesn't control. Share only what you're happy for
that app, and the people you send it to, to see.

## Focus Guard (Android, optional)

Focus Guard helps you stay aware of time spent in apps you choose. It sends
one gentle reminder on a day when those apps together reach the daily
budget you set. **It does not block apps.**

- **Off until you turn it on.** You choose the apps and the budget; nothing
  is picked for you. Restoring a backup leaves it off.
- **Android's Usage Access is required**, and only you can grant it, on a
  system settings page NextRep opens when you tap "Allow Usage Access".
  You can revoke it there at any time; Focus Guard then stops measuring.
- **Notification permission is separate.** Usage Access lets Focus Guard
  measure; notifications let it send its reminder. Without notifications it
  still shows today's time in the app, but sends nothing.
- **Today's usage comes from Android** each time it is needed: the
  foreground time of the apps you chose, from local midnight until now. It
  is shown and compared with your budget, then discarded. It is **never
  stored**: no per-app or per-day usage, no history, no timeline of when
  you used what.
- What NextRep stores is only what you chose (on or off, the apps' package
  names, the budget) and the date of the last reminder, so it never sends
  two on the same day. App names and icons are read from Android when shown
  and are not stored.
- **Nothing is uploaded.** No usage, app list, reminder history or device
  identifier leaves the device. NextRep still has no `INTERNET` permission.
- It does not read the content of other apps, your messages, notifications,
  browsing history or websites. It uses no Accessibility service, overlay,
  VPN or notification access, and it can't see apps that have no launcher
  icon (it doesn't request `QUERY_ALL_PACKAGES`).
- **Background checks are best effort.** Android runs Focus Guard's check
  when it can, usually around every 15 minutes, sometimes much later. If
  NextRep is force-stopped, checks resume when you open it again. The
  reminder can therefore arrive late; it is never exact or real-time.
- Reaching the budget changes nothing else: no XP, streak, achievement or
  Perfect Day is affected, and it never appears on a share card.
- Focus Guard is not available on iPhone.

## Backups you export

- A backup is made only when you tap **Export Backup**. You then choose
  where to save it in the system file dialog (for example Files, Drive or a
  USB drive).
- The file contains all of the data above, **including your reflections**.
- If you chose apps for Focus Guard, the file also contains **their package
  names** (which reveal which apps you wanted to limit) and your daily
  budget. It never contains whether Focus Guard was on, its last reminder,
  or any app-usage time.
- **Backup files are not encrypted by NextRep.** Anyone who can open the
  file can read it. Store it somewhere you trust. The app says this before
  every export.
- The backup includes a checksum so accidental corruption can be detected.
  The checksum is not a security feature: it doesn't make the file secure,
  private or tamper-proof.
- Restoring reads only the file you pick. It replaces the data on the device
  after you confirm twice, and reminders (Hydration Coach included) come
  back turned off. Focus Guard keeps the restored apps and budget but is
  **off**, with its background check cancelled, until you turn it on again.
  A restore never asks for Usage Access or notification permission.

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
  today go?", "Hydration check"). It never includes your habits, amounts,
  goals or reflections.
- Hydration Coach reads your Water progress on the device to decide whether
  to nudge you. Nothing about it leaves the device.
- Focus Guard's reminder ("You've reached today's 60-minute Focus Guard
  budget. Time to come back to your Arc?") names only your budget: never an
  app or an amount of usage. It has its own notification channel, so you
  can silence it separately.
- If you turn notifications off in system settings, NextRep keeps your
  reminder setting, tells you notifications are off and doesn't ask again.

## Permissions (Android release build)

| Permission | Why |
|---|---|
| `POST_NOTIFICATIONS` | show the optional reminders (Android 13+, asked when you turn one on) |
| `VIBRATE` | notification and haptic feedback |
| `RECEIVE_BOOT_COMPLETED` | re-schedule pending reminders after a restart (and, through Android's WorkManager, Focus Guard's check) |
| `PACKAGE_USAGE_STATS` | Focus Guard only: read today's foreground time of the apps you chose. Android grants it only when you switch on Usage Access in system settings |
| `WAKE_LOCK` | Android's WorkManager, which runs Focus Guard's short background check |
| `com.nextrep.nextrep.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION` | an app-private AndroidX permission; it grants nothing to other apps |

The app requests no storage, media, photo or contacts permission, no
network-state, foreground-service, overlay or every-package-visibility
permission, and declares no Accessibility, VPN or notification-listener
service. Backups go through the system document picker, and share cards
through the system share sheet. It requests no exact-alarm permission:
reminders may arrive a few minutes late. `INTERNET` appears only in debug and profile builds,
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

NextRep is an open-source project published by its developer on GitHub.
For privacy questions, open an issue in the
[NextRep repository](https://github.com/arunachaleswaranms/NextRep/issues).
Don't include reflections, backup files or other personal data in an
issue: issues are public.
