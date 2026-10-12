import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../app/theme/winter_tokens.dart';
import '../../../shared/winter_scene/scene_progress.dart';
import '../../achievements/widgets/achievement_badge.dart';
import '../share_card_data.dart';
import 'share_card_frame.dart';

// The three share cards. Each renders one immutable snapshot on the fixed
// share canvas; layouts are bounded (row heights from the space left,
// single-line titles with ellipsis), so up to 12 habits with 40-character
// names always fit without overflow.

/// Today's Progress: the day, the completion count, every habit's status
/// (or anonymous dots when names are hidden) and the stats the user chose
/// to show.
class TodayShareCard extends StatelessWidget {
  const TodayShareCard({super.key, required this.data});

  final TodayShareCardData data;

  @override
  Widget build(BuildContext context) {
    final colors = context.winter;
    final done = data.minimumDay ? colors.recovery : colors.accentSecondary;
    final stats = [
      if (data.level case final level?)
        _Stat(value: '$level', caption: 'LEVEL'),
      if (data.totalXp case final xp?) _Stat(value: '$xp', caption: 'XP'),
      if (data.streak case final streak?)
        _Stat(
          value: streak.daysLabel,
          caption: streak.label.toUpperCase(),
          flex: 3,
        ),
    ];
    return ShareCardFrame(
      scene: SceneProgress(
        dayNumber: data.dayNumber ?? 1,
        totalDays: data.arc.totalDays,
        dayCompletion: data.total == 0 ? 0 : data.completed / data.total,
        perfect: data.perfectDay,
        minimum: data.minimumDay,
      ),
      label: 'TODAY',
      tagline: data.tagline,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 22),
          _Eyebrow(data.headline),
          const SizedBox(height: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerStart,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  '${data.completed} / ${data.total}',
                  style: const TextStyle(
                    fontSize: 46,
                    height: 1,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -1,
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  'COMPLETE',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 2.4,
                    color: colors.snow.withValues(alpha: 0.85),
                  ),
                ),
              ],
            ),
          ),
          if (data.minimumDay || data.perfectDay) ...[
            const SizedBox(height: 10),
            data.minimumDay
                ? ShareCardPill(label: 'MINIMUM DAY', color: colors.recovery)
                : ShareCardPill(
                    label: 'PERFECT DAY',
                    color: colors.celebration,
                  ),
          ],
          const SizedBox(height: 16),
          Expanded(
            child: data.showsHabitNames
                ? _HabitGrid(habits: data.habits, minimum: data.minimumDay)
                : _HabitDots(
                    habits: data.habits,
                    color: done,
                    summary:
                        '${data.completed} of ${data.total} habits complete',
                  ),
          ),
          if (stats.isNotEmpty) ...[
            const SizedBox(height: 12),
            _StatRow(stats: stats),
          ],
        ],
      ),
    );
  }
}

/// My Arc: the habits and full goals of the user's current arc.
class ArcShareCard extends StatelessWidget {
  const ArcShareCard({super.key, required this.data});

  final ArcShareCardData data;

  @override
  Widget build(BuildContext context) {
    final colors = context.winter;
    return ShareCardFrame(
      scene: SceneProgress(dayNumber: 1, totalDays: data.arc.totalDays),
      label: 'MY ARC',
      tagline: data.tagline,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 24),
          Text(
            data.headline,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 23,
              height: 1.1,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            data.subtitle,
            style: TextStyle(
              fontSize: 11.5,
              color: colors.snow.withValues(alpha: 0.8),
            ),
          ),
          const SizedBox(height: 18),
          Expanded(child: _GoalGrid(goals: data.goals)),
          const SizedBox(height: 14),
          _Route(start: data.startLabel, end: data.endLabel),
        ],
      ),
    );
  }
}

/// Achievement: the badge, title, criterion and the challenge day it was
/// unlocked on.
class AchievementShareCard extends StatelessWidget {
  const AchievementShareCard({super.key, required this.data});

  final AchievementShareCardData data;

  @override
  Widget build(BuildContext context) {
    final colors = context.winter;
    final accent = data.key.accent(colors);
    return ShareCardFrame(
      scene: SceneProgress(dayNumber: data.dayNumber),
      label: 'ACHIEVEMENT',
      tagline: data.tagline,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          AchievementBadge(achievement: data.key, unlocked: true, size: 116),
          const SizedBox(height: 18),
          Text(
            data.title.toUpperCase(),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 26,
              height: 1.1,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            data.description,
            textAlign: TextAlign.center,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13.5,
              color: colors.snow.withValues(alpha: 0.8),
            ),
          ),
          const SizedBox(height: 16),
          ShareCardPill(label: data.unlockedLabel, color: accent),
        ],
      ),
    );
  }
}

class _Eyebrow extends StatelessWidget {
  const _Eyebrow(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    style: TextStyle(
      fontSize: 10.5,
      fontWeight: FontWeight.w800,
      letterSpacing: 2,
      color: context.winter.accentSecondary,
    ),
  );
}

/// Rows of [count] items in one column up to six, two above, each row as
/// tall as the space allows up to [maxRowHeight].
class _BoundedGrid extends StatelessWidget {
  const _BoundedGrid({
    required this.count,
    required this.maxRowHeight,
    required this.itemBuilder,
    this.twoColumnsFrom = 7,
  });

  final int count;
  final double maxRowHeight;
  final int twoColumnsFrom;
  final Widget Function(BuildContext context, int index, double height)
  itemBuilder;

  static const double _gap = 6;

  @override
  Widget build(BuildContext context) {
    if (count == 0) return const SizedBox.shrink();
    final columns = count >= twoColumnsFrom ? 2 : 1;
    final rows = (count / columns).ceil();
    return LayoutBuilder(
      builder: (context, constraints) {
        final fit = (constraints.maxHeight - _gap * (rows - 1)) / rows;
        final height = math.max(0.0, math.min(maxRowHeight, fit));
        return Column(
          children: [
            for (var row = 0; row < rows; row++) ...[
              if (row > 0) const SizedBox(height: _gap),
              SizedBox(
                height: height,
                child: Row(
                  children: [
                    for (var column = 0; column < columns; column++) ...[
                      if (column > 0) const SizedBox(width: _gap),
                      Expanded(
                        child: row * columns + column < count
                            ? itemBuilder(
                                context,
                                row * columns + column,
                                height,
                              )
                            : const SizedBox.shrink(),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

class _HabitGrid extends StatelessWidget {
  const _HabitGrid({required this.habits, required this.minimum});

  final List<TodayShareHabit> habits;
  final bool minimum;

  @override
  Widget build(BuildContext context) {
    final colors = context.winter;
    return _BoundedGrid(
      count: habits.length,
      maxRowHeight: 32,
      itemBuilder: (context, index, height) {
        final habit = habits[index];
        final accent = minimum
            ? colors.recovery
            : WinterHabitAccents.of(habit.iconKey ?? '');
        final font = (height * 0.46).clamp(8.0, 13.0);
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: colors.glass,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: habit.done
                  ? accent.withValues(alpha: 0.55)
                  : colors.glassBorder,
            ),
          ),
          child: Row(
            children: [
              Icon(
                habit.done
                    ? Icons.check_circle_rounded
                    : Icons.radio_button_unchecked_rounded,
                size: font + 3,
                color: habit.done ? accent : colors.textSecondary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  habit.title ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: font,
                    fontWeight: FontWeight.w600,
                    color: habit.done
                        ? colors.textPrimary
                        : colors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// The privacy-safe summary when habit names are hidden: one dot per habit,
/// filled when done, with no names or icons.
class _HabitDots extends StatelessWidget {
  const _HabitDots({
    required this.habits,
    required this.color,
    required this.summary,
  });

  final List<TodayShareHabit> habits;
  final Color color;
  final String summary;

  @override
  Widget build(BuildContext context) {
    final colors = context.winter;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final habit in habits)
                Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: habit.done ? color : colors.glass,
                    border: Border.all(
                      color: habit.done ? color : colors.textSecondary,
                      width: 1.4,
                    ),
                  ),
                  child: habit.done
                      ? Icon(
                          Icons.check_rounded,
                          size: 14,
                          color: colors.background,
                        )
                      : null,
                ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            summary,
            style: TextStyle(
              fontSize: 12,
              color: colors.snow.withValues(alpha: 0.8),
            ),
          ),
        ],
      ),
    );
  }
}

class _Stat {
  const _Stat({required this.value, required this.caption, this.flex = 1});

  final String value;
  final String caption;
  final int flex;
}

class _StatRow extends StatelessWidget {
  const _StatRow({required this.stats});

  final List<_Stat> stats;

  @override
  Widget build(BuildContext context) {
    final colors = context.winter;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: colors.glass,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.glassBorder),
      ),
      child: Row(
        children: [
          for (final (index, stat) in stats.indexed) ...[
            if (index > 0)
              Container(
                width: 1,
                height: 26,
                margin: const EdgeInsets.symmetric(horizontal: 10),
                color: colors.glassBorder,
              ),
            Expanded(
              flex: stat.flex,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    stat.value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15,
                      height: 1.1,
                      fontWeight: FontWeight.w800,
                      color: colors.celebration,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    stat.caption,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 8,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.2,
                      color: colors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _GoalGrid extends StatelessWidget {
  const _GoalGrid({required this.goals});

  final List<ArcShareGoal> goals;

  @override
  Widget build(BuildContext context) {
    final colors = context.winter;
    return _BoundedGrid(
      count: goals.length,
      maxRowHeight: 50,
      twoColumnsFrom: 4,
      itemBuilder: (context, index, height) {
        final goal = goals[index];
        final title = (height * 0.34).clamp(8.0, 13.5);
        final target = (height * 0.28).clamp(7.5, 11.5);
        return Container(
          padding: const EdgeInsets.only(right: 10),
          decoration: BoxDecoration(
            color: colors.glass,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: colors.glassBorder),
          ),
          clipBehavior: Clip.antiAlias,
          child: Row(
            children: [
              Container(width: 3, color: WinterHabitAccents.of(goal.iconKey)),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      goal.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: title,
                        height: 1.15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      goal.target,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: target,
                        height: 1.15,
                        color: colors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// "DAY 1 ——→ DAY 92": the arc from where the user starts to its end.
class _Route extends StatelessWidget {
  const _Route({required this.start, required this.end});

  final String start;
  final String end;

  @override
  Widget build(BuildContext context) {
    final colors = context.winter;
    final style = TextStyle(
      fontSize: 10.5,
      fontWeight: FontWeight.w800,
      letterSpacing: 1.6,
      color: colors.snow,
    );
    return Row(
      children: [
        Text(start, style: style),
        const SizedBox(width: 10),
        Expanded(
          child: Container(
            height: 2,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(WinterRadii.pill),
              gradient: LinearGradient(
                colors: [colors.accentSecondary, colors.celebration],
              ),
            ),
          ),
        ),
        Icon(Icons.chevron_right_rounded, size: 16, color: colors.celebration),
        const SizedBox(width: 4),
        Text(end, style: style.copyWith(color: colors.celebration)),
      ],
    );
  }
}
