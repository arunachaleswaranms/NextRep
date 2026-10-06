# Store metadata (release-candidate draft)

Draft listing copy. Nothing here has been published. Each claim matches
what the app does today. Keep it that way when editing: no "scientifically
proven", no guaranteed results, no health or mental-health claims.

## App name

**NextRep**

Subtitle / short name (App Store subtitle, max 30 characters):

> Winter Arc habit challenge

## Short description (Play, max 80 characters)

> A private 92-day Winter Arc for your daily habits. Local-first, no account.

(75 characters.)

## Long description

> **NextRep turns your daily habits into a 92-day climb.**
>
> Pick a few habits, show up each day, and watch your Winter Arc move from
> a frozen trail toward a warm summit. Everything stays on your phone.
>
> **Two ways to run your Arc**
> • **Rolling 92-Day Arc**: start whenever you're ready. Day 1 is the day
>   you press Start.
> • **Seasonal Winter Arc**: October 1 – December 31, the same season for
>   everyone. Set it up in September, or join late; the days before you
>   join don't count against you.
>
> **Habits your way**
> • Start from templates or create your own.
> • Track done / not done, counts, minutes, or "before a time" habits such
>   as Sleep Before Target.
> • Up to 12 habits per Arc.
>
> **Keep moving on hard days**
> A **Minimum Day** scales today down to each habit's essential version, so
> your streaks continue even when the day is smaller. Finish everything on
> a normal day for a **Perfect Day**.
>
> **See the climb**
> • Earn XP and level up.
> • Follow your **Journey**: 92 days on a mountain path, chapter by chapter.
> • Unlock achievements along the way.
> • **Insights** across your Arcs: consistency, Perfect and Minimum Days,
>   your strongest habits and the moods you logged.
>
> **A 20-second Journal**
> Each evening, pick a mood, note one win and one thing to improve. Only
> today is editable; past entries are kept as they were.
>
> **Private by design**
> • No account and no sign-in.
> • No ads, analytics or tracking.
> • The app has no network access. Your data stays on your device.
> • Optional local reminders, off until you turn them on.
> • Export a backup file when you choose, and restore it on a new phone.
>   Backup files are not encrypted, so keep them somewhere you trust.

## Keywords / search terms

App Store keywords field (100 characters, comma-separated, no spaces):

```
winter arc,habit tracker,habits,streak,92 day challenge,routine,self improvement,journal,goals
```

Play has no keyword field. Use these naturally in the description:
winter arc, habit tracker, 92-day challenge, streaks, daily routine,
offline habit tracker, private journal.

## Category

- Play: Health & Fitness (alternative: Productivity)
- App Store: Health & Fitness (secondary: Productivity)

## Screenshots

Use synthetic data only: no personal data and no demo code in the app.
The deterministic states come from a synthetic backup made by a dev-only
tool. That tool runs the app's own services on an in-memory database and
exports with the real backup service, so the file passes normal
validation.

```bash
# The active arc ends on this date: use the capture device's date.
SCREENSHOT_DATE=2026-10-06 flutter test tool/screenshots/generate_screenshot_backup.dart
# → build/screenshots/nextrep-screenshots-2026-10-06.nextrep
```

The file holds two invented arcs:

- Last year's Seasonal Winter Arc, joined late on 15 October and finished
  at the summit: 57 Perfect Days, all 15 achievements.
- A Rolling Arc on Day 20 on the capture date. Today 3 of 6 habits are
  done, including the custom "Stretch" habit and Sleep Before Target.

There are 47 invented reflections in total.

### Capture (Android, release build)

1. Install the release APK on a clean emulator or test phone.
2. Copy the file to Downloads.
3. In onboarding, choose **Restore from a backup**, then pick the file.
4. Fix the frame. Play allows a long side of at most twice the short side,
   so a 1280 × 2856 AVD needs a 2:1 size, and the status bar should be
   clean:

   ```bash
   adb shell wm size 1080x2160 && adb shell wm density 420
   adb shell settings put global sysui_demo_allowed 1
   adb shell am broadcast -a com.android.systemui.demo -e command enter
   adb shell am broadcast -a com.android.systemui.demo -e command clock -e hhmm 0930
   adb shell am broadcast -a com.android.systemui.demo -e command battery -e level 100 -e plugged false
   adb shell am broadcast -a com.android.systemui.demo -e command network -e mobile hide -e wifi show -e level 4 -e fully true
   adb shell am broadcast -a com.android.systemui.demo -e command notifications -e visible false
   ```

5. Capture with `adb exec-out screencap -p > NN_name.png`, in the order
   below.
6. Reset the device afterwards:

   ```bash
   adb shell wm size reset && adb shell wm density reset
   adb shell am broadcast -a com.android.systemui.demo -e command exit
   ```

| # | Screen | Story | How to reach it | Caption | Captured (Phase 8) |
|---|---|---|---|---|---|
| 1 | Today | the daily loop | opens on Today (Day 20, 3 of 6 done, Level 8) | "Show up every day. Watch the climb." | yes |
| 2 | Journey | progress as a place | Journey tab (today's marker, Perfect, partial days) | "92 days on one mountain trail." | yes |
| 3 | Seasonal Journey | joining late is fine | History, then the 2025 Seasonal arc, then View Journey, scrolled to Days 9–15 (dashed "Before you joined") | "Join the season late. Earlier days don't count against you." | yes |
| 4 | Perfect Day | reward | on Today, finish No Junk Food, Stretch and Sleep Before Target; capture the Perfect Day / Level 9 card | "Perfect Days, levels and achievements." | yes |
| 5 | Journal | reflection | Journal tab (today's synthetic entry and past entries) | "A 20-second evening reflection." | yes |
| 6 | Insights | understanding | History, then Insights | "Insights computed on your phone." | yes |
| 7 | Arc Summary | completion | History, then the 2025 Seasonal arc (summit summary) | "Reach the summit." | yes |
| 8 | Habit Setup | getting started | clear app data, then Let's Begin, Rolling 92-Day, turn on Sleep Before Target, add a custom "Stretch" (Minutes) | "Templates or your own habits, up to 12." | yes |

The Phase 8 captures are drafts: 1080 × 2160 PNGs from the API 36
emulator, in the release build, kept in `build/screenshots/` (not in git,
not uploaded). Retake them after any UI change and after the final
version is chosen.

Sizes still needed:

- Play: phone, 2 to 8 screenshots; each side 320–3840 px, long side at
  most 2× the short side. 1080 × 2160 is done.
- App Store: 6.9" iPhone (1320 × 2868) or 6.7" (1290 × 2796).
  - Capture on the matching simulator with the same backup restored
    through Files.
  - iPad 13" screenshots are also required while iPad support stays
    enabled (`TARGETED_DEVICE_FAMILY = 1,2`).
  - **Not captured yet.**

## Graphics

- App icon: `assets/branding/store/play_store_icon_512.png` (Play) and
  `assets/branding/store/app_store_icon_1024.png` (App Store). Both are
  generated from `tool/brand_assets/generate_brand_assets.dart`.
- Play feature graphic (1024 × 500): **MANUAL STORE ASSET**, not made.
  Concept, from the existing branding only:
  - the night-sky gradient (`skyTop` → `skyHorizon`) across the full width
  - the two snow peaks and saddle from `assets/branding/nextrep_icon.svg`
    on the left third, with the warm summit light above the higher peak
  - "NextRep" in white and one line, "Your 92-day Winter Arc", on the
    right
  - no device frames, screenshots, badges or third-party artwork
  - keep the text clear of the outer 10% (Play may crop or overlay it)

## Release notes (first release, draft)

> The first release of NextRep: a private, local-first Winter Arc. Run a
> Rolling 92-Day Arc or join the Seasonal Winter Arc (October 1 – December
> 31), track habits your way, keep going with Minimum Days, follow your
> Journey, reflect in the Journal, and back up your data whenever you
> choose.
