import 'dart:math';

import '../../core/errors/app_failure.dart';
import 'habit.dart';
import 'habit_config.dart';
import 'habit_edit.dart';
import 'habit_template_catalog.dart';

/// What the user entered for a habit they create or change during setup.
///
/// Only the fields its [type] uses are read: a done / not-done habit has
/// no numbers, a clock-time habit only a [target] time (its Minimum Day
/// target is the same), count and duration habits a [target] and a
/// [minimumTarget]. Anything else is ignored, so a value left behind by a
/// type the user switched away from can't leak into the habit.
final class HabitDraft {
  const HabitDraft({
    required this.title,
    required this.type,
    required this.iconKey,
    this.target,
    this.minimumTarget,
    this.unit,
  });

  final String title;
  final HabitType type;
  final String iconKey;

  /// Normal target; a normalized [NightTime] value for a clock-time habit.
  final int? target;

  /// Minimum Day target of a count or duration habit.
  final int? minimumTarget;

  /// Unit of a count habit ("glasses", "pages").
  final String? unit;
}

/// Creates the stable id of a habit the user makes up.
abstract interface class HabitIdGenerator {
  String next();
}

/// `custom_` followed by 128 random bits as 32 lowercase hex digits, from
/// the platform's secure random source. Local, no network, never derived
/// from the title, so renaming never changes a habit's identity.
final class SecureHabitIdGenerator implements HabitIdGenerator {
  SecureHabitIdGenerator([Random? random])
    : _random = random ?? Random.secure();

  final Random _random;

  @override
  String next() {
    final hex = StringBuffer();
    for (var i = 0; i < 16; i++) {
      hex.write(_random.nextInt(256).toRadixString(16).padLeft(2, '0'));
    }
    return '${SetupHabitRules.customIdPrefix}$hex';
  }
}

/// Icons a habit the user creates can have. Presentation keys only; the UI
/// maps them to glyphs.
abstract final class HabitIconKeys {
  static const List<String> all = [
    'workout',
    'water',
    'learning',
    'english',
    'no_junk_food',
    'sleep',
    'meditation',
    'journal',
    'walk',
    'music',
    'code',
    'nature',
    'heart',
    'star',
  ];

  static const fallback = 'star';
}

/// Rules for the habits of an arc that hasn't started yet.
///
/// While an arc is in setup there is no history, so habits are created,
/// changed and deleted directly (no revisions). Once it starts, habits can
/// only be renamed, re-targeted from the next day or switched off: adding
/// or deleting a habit of a running arc would need a dated "exists from"
/// history that doesn't exist yet.
abstract final class SetupHabitRules {
  /// Most habits one arc can have.
  static const int maxHabits = 12;

  static const String customIdPrefix = 'custom_';
  static final _customId = RegExp(r'^custom_[0-9a-f]{32}$');

  static const int maxUnitLength = 16;

  /// The unit of a count habit when none is given.
  static const String defaultCountUnit = 'times';

  static bool isCustomId(String id) => _customId.hasMatch(id);

  /// Throws [DomainRule.habitLimitReached] if [existing] habits leave no
  /// room for another one.
  static void checkRoom(int existing) {
    if (existing >= maxHabits) {
      throw const DomainFailure(
        DomainRule.habitLimitReached,
        'An arc has at most $maxHabits habits',
      );
    }
  }

  /// The habit [template] adds to a setup that already has [habits].
  ///
  /// Throws [DomainRule.duplicateHabit] if the template (by id) or a habit
  /// with the same name is already there.
  static Habit fromTemplate(
    HabitTemplate template,
    List<Habit> habits, {
    required DateTime createdAt,
  }) {
    checkRoom(habits.length);
    if (habits.any((h) => h.id == template.id)) {
      throw DomainFailure(
        DomainRule.duplicateHabit,
        'Template "${template.id}" is already in this arc',
      );
    }
    _checkTitleFree(template.title, habits);
    return template.toHabit(
      sortOrder: _nextSortOrder(habits),
      createdAt: createdAt,
      enabled: true,
    );
  }

  /// A new habit from [draft], with [id], for a setup that already has
  /// [habits]. Enabled.
  static Habit create(
    HabitDraft draft,
    List<Habit> habits, {
    required String id,
    required DateTime createdAt,
  }) {
    checkRoom(habits.length);
    if (!isCustomId(id) || habits.any((h) => h.id == id)) {
      throw DomainFailure(DomainRule.duplicateHabit, 'Habit id is not new');
    }
    final valid = _validate(draft);
    _checkTitleFree(valid.title, habits);
    return Habit(
      id: id,
      title: valid.title,
      type: draft.type,
      target: valid.config.target,
      minimumTarget: valid.config.minimumTarget,
      unit: valid.unit,
      iconKey: draft.iconKey,
      enabled: true,
      sortOrder: _nextSortOrder(habits),
      createdAt: createdAt,
    );
  }

  /// [habit] changed to [draft], among the setup's [habits]. The type can't
  /// change (delete the habit and add another instead); the id, enabled
  /// state, order and creation time are kept.
  static Habit edit(Habit habit, HabitDraft draft, List<Habit> habits) {
    if (draft.type != habit.type) {
      throw DomainFailure(
        DomainRule.invalidHabitEdit,
        'The type of "${habit.id}" cannot change',
      );
    }
    final valid = _validate(draft, keepIcon: habit.iconKey);
    _checkTitleFree(valid.title, [
      for (final h in habits)
        if (h.id != habit.id) h,
    ]);
    return Habit(
      id: habit.id,
      title: valid.title,
      type: habit.type,
      target: valid.config.target,
      minimumTarget: valid.config.minimumTarget,
      unit: valid.unit,
      iconKey: draft.iconKey,
      enabled: habit.enabled,
      sortOrder: habit.sortOrder,
      createdAt: habit.createdAt,
    );
  }

  /// The trimmed title and the configuration [draft] describes. Throws
  /// [DomainRule.invalidHabitEdit] for anything out of bounds.
  ///
  /// [keepIcon] is an existing habit's icon, accepted as it is.
  static ({String title, HabitConfig config, String? unit}) _validate(
    HabitDraft draft, {
    String? keepIcon,
  }) {
    Never invalid(String why) =>
        throw DomainFailure(DomainRule.invalidHabitEdit, why);

    final title = draft.title.trim();
    if (title.isEmpty || title.length > HabitEditRules.maxTitleLength) {
      invalid('Title must be 1..${HabitEditRules.maxTitleLength} characters');
    }
    if (draft.iconKey != keepIcon &&
        !HabitIconKeys.all.contains(draft.iconKey)) {
      invalid('Unknown icon');
    }

    final type = draft.type;
    final config = switch (type) {
      HabitType.binary => const HabitConfig(
        target: 1,
        minimumTarget: 1,
        enabled: true,
      ),
      HabitType.timeBefore => HabitConfig(
        target: draft.target ?? invalid('A clock-time habit needs a time'),
        minimumTarget: draft.target!,
        enabled: true,
      ),
      HabitType.count || HabitType.duration => HabitConfig(
        target: draft.target ?? invalid('A target is required'),
        minimumTarget: draft.minimumTarget ?? draft.target!,
        enabled: true,
      ),
    };
    if (!HabitEditRules.isValidConfig(type, config)) {
      invalid('Target out of range for a ${type.name} habit');
    }

    final unit = switch (type) {
      HabitType.count => () {
        final text = draft.unit?.trim() ?? '';
        if (text.length > maxUnitLength) invalid('Unit is too long');
        return text.isEmpty ? defaultCountUnit : text;
      }(),
      HabitType.duration => 'min',
      HabitType.binary || HabitType.timeBefore => null,
    };
    return (title: title, config: config, unit: unit);
  }

  /// Throws [DomainRule.duplicateHabit] if one of [habits] already has
  /// [title], ignoring case and surrounding spaces.
  static void _checkTitleFree(String title, List<Habit> habits) {
    final key = normalizeTitle(title);
    if (habits.any((h) => normalizeTitle(h.title) == key)) {
      throw const DomainFailure(
        DomainRule.duplicateHabit,
        'A habit with this name is already in this arc',
      );
    }
  }

  /// [title] for duplicate checks: trimmed, inner spaces collapsed,
  /// lower case.
  static String normalizeTitle(String title) =>
      title.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();

  static int _nextSortOrder(List<Habit> habits) =>
      habits.isEmpty ? 0 : habits.map((h) => h.sortOrder).reduce(max) + 1;
}
