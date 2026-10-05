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

Capture on a real device or emulator in release mode. Use real, invented
habits typed in by hand: no personal data, and no debug or demo code in the
app. NextRep ships no screenshot fixture.

| # | Screen | State to set up | Caption |
|---|---|---|---|
| 1 | Today | mid-arc (around Day 20), 3 of 5 habits done, XP bar part-way | "Show up every day. Watch the climb." |
| 2 | Journey | a few weeks in, mixed Perfect / Minimum Days, today's marker lit | "92 days on one mountain trail." |
| 3 | Seasonal Journey | a late-joined Seasonal Arc showing the dashed "Before you joined" days | "Join the season late. Earlier days don't count against you." |
| 4 | Perfect Day / achievement | the Perfect Day or an achievement card just after the last habit | "Perfect Days, levels and achievements." |
| 5 | Journal | today's reflection with a mood picked | "A 20-second evening reflection." |
| 6 | Insights | after one completed Arc, consistency, habits and moods visible | "Insights computed on your phone." |
| 7 | Arc Summary | a completed Arc's summit summary | "Reach the summit." |
| 8 | Habit Setup | templates plus one custom habit, Sleep Before Target on | "Templates or your own habits, up to 12." |

Sizes:

- Play: phone 16:9 or 9:16, 1080 × 1920 or larger.
- App Store: 6.9" iPhone (1320 × 2868) or 6.7" (1290 × 2796). iPad 13"
  screenshots are required while iPad support stays enabled
  (`TARGETED_DEVICE_FAMILY = 1,2`). Restricting the app to iPhone is a
  separate decision.

## Graphics

- App icon: `assets/branding/store/play_store_icon_512.png` (Play) and
  `assets/branding/store/app_store_icon_1024.png` (App Store). Both are
  generated from `tool/brand_assets/generate_brand_assets.dart`.
- Play feature graphic (1024 × 500): **manual**. Suggested composition: the
  night sky and mountain ridge from the icon on the left, "NextRep" and
  "Your 92-day Winter Arc" on the right. No device frames and no
  third-party artwork.

## Release notes (first release, draft)

> The first release of NextRep: a private, local-first Winter Arc. Run a
> Rolling 92-Day Arc or join the Seasonal Winter Arc (October 1 – December
> 31), track habits your way, keep going with Minimum Days, follow your
> Journey, reflect in the Journal, and back up your data whenever you
> choose.
