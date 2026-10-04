import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../../core/errors/app_failure.dart';
import '../../core/time/local_date.dart';
import '../achievement/achievement.dart';
import '../habit/habit.dart';
import '../habit/habit_config.dart';
import '../progress/daily_habit_progress.dart';
import '../progress/day_mode.dart';
import '../reflection/daily_reflection.dart';
import '../reminder/reminder_preferences.dart';
import '../winter_arc/winter_arc_session.dart';
import '../xp/xp.dart';
import 'backup_document.dart';

/// Reads and writes the NextRep backup file format, version 1.
///
/// A backup is a UTF-8 JSON object:
///
/// ```json
/// {
///   "appVersion": "1.0.0",
///   "checksum": {"algorithm": "sha256", "value": "<64 hex digits>"},
///   "data": {"arcs": [...], "reminders": {...} | null},
///   "exportedAt": "2026-10-04T09:00:00.000Z",
///   "formatVersion": 1,
///   "product": "NextRep"
/// }
/// ```
///
/// Field names describe the domain (`habits`, `progress`, `xp`, ...), not
/// database tables or columns, so the file doesn't change when the schema
/// does. Enum values are written by their stable persisted names.
///
/// **Checksum.** `checksum.value` is the SHA-256 of the canonical encoding
/// of every other top-level field (see [canonicalJson]). It detects
/// accidental damage (a truncated download, a flipped byte, a hand edit).
/// It is not encryption, authentication or a signature: anyone can edit a
/// backup and recompute it. The file itself is plain, unencrypted JSON.
///
/// [decode] checks, in order: size, UTF-8 JSON object, product, format
/// version, checksum, then every field's presence and type and the basic
/// value rules a domain object needs (e.g. a habit's target is positive).
/// Unknown fields are rejected rather than ignored, so nothing in a file is
/// silently dropped. Cross-record rules (references, uniqueness, dates
/// inside the arc) are checked afterwards by `BackupValidator`.
///
/// Error messages name the field and its position only, never a value.
abstract final class BackupCodec {
  /// Encodes [document] as canonical JSON with its checksum.
  static Uint8List encode(BackupDocument document) {
    final body = _documentToJson(document);
    final withChecksum = {
      ...body,
      'checksum': {
        'algorithm': BackupFormat.checksumAlgorithm,
        'value': checksumOf(body),
      },
    };
    return Uint8List.fromList(utf8.encode(canonicalJson(withChecksum)));
  }

  /// Decodes and checks a backup file. Throws [BackupFailure].
  static BackupDocument decode(Uint8List bytes) {
    if (bytes.length > BackupFormat.maxBytes) {
      throw const BackupFailure(
        BackupProblem.tooLarge,
        'Backup is over the size limit',
      );
    }
    final Object? json;
    try {
      var text = utf8.decode(bytes);
      if (text.startsWith('﻿')) text = text.substring(1);
      json = jsonDecode(text);
    } on FormatException {
      // The exception quotes the input, so it is not kept.
      throw const BackupFailure(
        BackupProblem.unreadable,
        'Backup is not UTF-8 JSON',
      );
    } on StackOverflowError {
      throw const BackupFailure(
        BackupProblem.unreadable,
        'Backup is nested too deeply',
      );
    }
    if (json is! Map<String, Object?>) {
      throw const BackupFailure(
        BackupProblem.unreadable,
        'Backup is not a JSON object',
      );
    }
    if (json['product'] != BackupFormat.product) {
      throw const BackupFailure(
        BackupProblem.notNextRep,
        'Backup product is not NextRep',
      );
    }
    final version = json['formatVersion'];
    if (version is! int) {
      throw const BackupFailure(
        BackupProblem.invalidData,
        'formatVersion is missing or not an integer',
      );
    }
    if (version != BackupFormat.formatVersion) {
      // A future format is never partially interpreted.
      throw BackupFailure(
        BackupProblem.unsupportedVersion,
        'Unsupported backup formatVersion $version',
      );
    }
    _verifyChecksum(json);

    final root = _Obj(json, r'$');
    root.only(const {
      'product',
      'formatVersion',
      'exportedAt',
      'appVersion',
      'data',
      'checksum',
    });
    return BackupDocument(
      exportedAt: root.timestamp('exportedAt'),
      appVersion: root.string('appVersion', maxLength: 64),
      data: _dataFromJson(root.object('data')),
    );
  }

  /// SHA-256 (lowercase hex) of the canonical encoding of [body].
  static String checksumOf(Map<String, Object?> body) =>
      sha256.convert(utf8.encode(canonicalJson(body))).toString();

  /// The canonical JSON encoding: object keys sorted by UTF-16 code units
  /// at every level, no insignificant whitespace, strings escaped as by
  /// `jsonEncode`. Only maps, lists, strings, integers, booleans and null
  /// are allowed (the format has no floating-point values), so the same
  /// data always encodes to the same bytes.
  static String canonicalJson(Object? value) {
    final out = StringBuffer();
    void write(Object? v) {
      switch (v) {
        case null || bool() || int() || String():
          out.write(jsonEncode(v));
        case Map<String, Object?>():
          final keys = v.keys.toList()..sort();
          out.write('{');
          for (final (i, key) in keys.indexed) {
            if (i > 0) out.write(',');
            out
              ..write(jsonEncode(key))
              ..write(':');
            write(v[key]);
          }
          out.write('}');
        case List<Object?>():
          out.write('[');
          for (final (i, item) in v.indexed) {
            if (i > 0) out.write(',');
            write(item);
          }
          out.write(']');
        default:
          throw ArgumentError('Not canonical JSON: ${v.runtimeType}');
      }
    }

    write(value);
    return out.toString();
  }

  static void _verifyChecksum(Map<String, Object?> json) {
    final checksum = json['checksum'];
    if (checksum is! Map<String, Object?> ||
        checksum.length != 2 ||
        checksum['algorithm'] != BackupFormat.checksumAlgorithm ||
        checksum['value'] is! String) {
      throw const BackupFailure(
        BackupProblem.checksumMismatch,
        'Backup checksum is missing or malformed',
      );
    }
    final body = {...json}..remove('checksum');
    final String expected;
    try {
      expected = checksumOf(body);
    } on ArgumentError {
      // E.g. a floating-point number somewhere: not something we wrote.
      throw const BackupFailure(
        BackupProblem.checksumMismatch,
        'Backup contains values outside the format',
      );
    } on StackOverflowError {
      throw const BackupFailure(
        BackupProblem.unreadable,
        'Backup is nested too deeply',
      );
    }
    if (checksum['value'] != expected) {
      throw const BackupFailure(
        BackupProblem.checksumMismatch,
        'Backup checksum does not match its contents',
      );
    }
  }

  // ---------------------------------------------------------------------
  // Writing

  static Map<String, Object?> _documentToJson(BackupDocument d) => {
    'product': BackupFormat.product,
    'formatVersion': BackupFormat.formatVersion,
    'exportedAt': _timestamp(d.exportedAt),
    'appVersion': d.appVersion,
    'data': {
      'arcs': [for (final arc in d.data.arcs) _arcToJson(arc)],
      'reminders': switch (d.data.reminders) {
        null => null,
        final r => {
          'dailyTime': _time(r.daily),
          'reflectionTime': _time(r.reflection),
        },
      },
    },
  };

  static Map<String, Object?> _arcToJson(BackupArc arc) {
    final s = arc.session;
    return {
      'id': s.id,
      'status': s.status.name,
      'startDate': s.startDate.toIsoString(),
      'endDate': s.endDate.toIsoString(),
      'createdAt': _timestamp(s.createdAt),
      'startedAt': _optTimestamp(s.startedAt),
      'habits': [
        for (final h in arc.habits)
          {
            'id': h.id,
            'title': h.title,
            'type': h.type.name,
            'target': h.target,
            'minimumTarget': h.minimumTarget,
            'unit': h.unit,
            'icon': h.iconKey,
            'enabled': h.enabled,
            'sortOrder': h.sortOrder,
            'createdAt': _timestamp(h.createdAt),
          },
      ],
      'habitRevisions': [
        for (final r in arc.revisions)
          {
            'habitId': r.habitId,
            'effectiveFrom': r.effectiveFrom.toIsoString(),
            'target': r.config.target,
            'minimumTarget': r.config.minimumTarget,
            'enabled': r.config.enabled,
            'createdAt': _timestamp(r.createdAt),
          },
      ],
      'dayModes': [
        for (final m in arc.dayModes)
          {
            'date': m.date.toIsoString(),
            'mode': m.mode.name,
            'changedAt': _timestamp(m.changedAt),
          },
      ],
      'progress': [
        for (final p in arc.progress)
          {
            'habitId': p.progress.habitId,
            'date': p.progress.date.toIsoString(),
            'value': p.progress.currentValue,
            'completed': p.progress.completed,
            'completedAt': _optTimestamp(p.progress.completedAt),
            'updatedAt': _timestamp(p.updatedAt),
          },
      ],
      'xp': [
        for (final x in arc.xp)
          {
            'sourceKey': x.sourceKey,
            'reason': x.reason.name,
            'amount': x.amount,
            'habitId': x.habitId,
            'date': x.date.toIsoString(),
            'createdAt': _timestamp(x.awardedAt),
          },
      ],
      'achievements': [
        for (final a in arc.achievements)
          {
            'key': a.key.id,
            'earnedOn': a.unlockedOn.toIsoString(),
            'unlockedAt': _timestamp(a.unlockedAt),
          },
      ],
      'reflections': [
        for (final r in arc.reflections)
          {
            'date': r.date.toIsoString(),
            'mood': r.mood?.key,
            'win': r.win,
            'improvement': r.improvement,
            'createdAt': _timestamp(r.createdAt),
            'updatedAt': _timestamp(r.updatedAt),
          },
      ],
    };
  }

  static String _timestamp(DateTime t) => t.toUtc().toIso8601String();

  static String? _optTimestamp(DateTime? t) => t == null ? null : _timestamp(t);

  static String _time(ReminderTime t) => t.toString();

  // ---------------------------------------------------------------------
  // Reading

  static BackupData _dataFromJson(_Obj data) {
    data.only(const {'arcs', 'reminders'});
    return BackupData(
      arcs: [for (final arc in data.objects('arcs')) _arcFromJson(arc)],
      reminders: switch (data.optObject('reminders')) {
        null => null,
        final r => () {
          r.only(const {'dailyTime', 'reflectionTime'});
          return BackupReminderTimes(
            daily: r.time('dailyTime'),
            reflection: r.time('reflectionTime'),
          );
        }(),
      },
    );
  }

  static BackupArc _arcFromJson(_Obj o) {
    o.only(const {
      'id',
      'status',
      'startDate',
      'endDate',
      'createdAt',
      'startedAt',
      'habits',
      'habitRevisions',
      'dayModes',
      'progress',
      'xp',
      'achievements',
      'reflections',
    });
    final id = o.integer('id', min: 1);
    return BackupArc(
      session: WinterArcSession(
        id: id,
        startDate: o.date('startDate'),
        endDate: o.date('endDate'),
        status: o.choice('status', WinterArcStatus.values, (v) => v.name),
        createdAt: o.timestamp('createdAt'),
        startedAt: o.optTimestamp('startedAt'),
      ),
      habits: [for (final h in o.objects('habits')) _habitFromJson(h)],
      revisions: [
        for (final r in o.objects('habitRevisions')) _revisionFromJson(r),
      ],
      dayModes: [
        for (final m in o.objects('dayModes'))
          () {
            m.only(const {'date', 'mode', 'changedAt'});
            return BackupDayMode(
              date: m.date('date'),
              mode: m.choice('mode', DayMode.values, (v) => v.name),
              changedAt: m.timestamp('changedAt'),
            );
          }(),
      ],
      progress: [
        for (final p in o.objects('progress'))
          () {
            p.only(const {
              'habitId',
              'date',
              'value',
              'completed',
              'completedAt',
              'updatedAt',
            });
            return BackupProgress(
              progress: DailyHabitProgress(
                habitId: p.string('habitId', maxLength: _maxIdLength),
                date: p.date('date'),
                currentValue: p.integer('value', min: 0, max: _maxValue),
                completed: p.boolean('completed'),
                completedAt: p.optTimestamp('completedAt'),
              ),
              updatedAt: p.timestamp('updatedAt'),
            );
          }(),
      ],
      xp: [
        for (final x in o.objects('xp'))
          () {
            x.only(const {
              'sourceKey',
              'reason',
              'amount',
              'habitId',
              'date',
              'createdAt',
            });
            return XpAward(
              sourceKey: x.string('sourceKey', maxLength: 200),
              reason: x.choice('reason', XpReason.values, (v) => v.name),
              amount: x.integer('amount', min: 1, max: 1000),
              habitId: x.optString('habitId', maxLength: _maxIdLength),
              date: x.date('date'),
              awardedAt: x.timestamp('createdAt'),
            );
          }(),
      ],
      achievements: [
        for (final a in o.objects('achievements'))
          () {
            a.only(const {'key', 'earnedOn', 'unlockedAt'});
            return AchievementUnlock(
              key: a.choice('key', AchievementKey.values, (v) => v.id),
              unlockedOn: a.date('earnedOn'),
              unlockedAt: a.timestamp('unlockedAt'),
            );
          }(),
      ],
      reflections: [
        for (final r in o.objects('reflections'))
          () {
            r.only(const {
              'date',
              'mood',
              'win',
              'improvement',
              'createdAt',
              'updatedAt',
            });
            return DailyReflection(
              sessionId: id,
              date: r.date('date'),
              mood: r.optChoice('mood', Mood.values, (v) => v.key),
              // Length (in characters) and emptiness are checked by the
              // validator, with the Journal's own rules. This bound only
              // keeps absurd values out: one character can take dozens of
              // UTF-16 units (e.g. a family emoji with skin tones).
              win: r.optString('win', maxLength: _maxReflectionUnits),
              improvement: r.optString(
                'improvement',
                maxLength: _maxReflectionUnits,
              ),
              createdAt: r.timestamp('createdAt'),
              updatedAt: r.timestamp('updatedAt'),
            );
          }(),
      ],
    );
  }

  static Habit _habitFromJson(_Obj h) {
    h.only(const {
      'id',
      'title',
      'type',
      'target',
      'minimumTarget',
      'unit',
      'icon',
      'enabled',
      'sortOrder',
      'createdAt',
    });
    final type = h.choice('type', HabitType.values, (v) => v.name);
    final config = _config(h, type);
    return Habit(
      id: h.string('id', maxLength: _maxIdLength),
      title: h.string('title', maxLength: 200),
      type: type,
      target: config.target,
      minimumTarget: config.minimumTarget,
      unit: h.optString('unit', maxLength: 32),
      iconKey: h.string('icon', maxLength: _maxIdLength),
      enabled: config.enabled,
      sortOrder: h.integer('sortOrder', min: 0, max: 9999),
      createdAt: h.timestamp('createdAt'),
    );
  }

  static HabitRevision _revisionFromJson(_Obj r) {
    r.only(const {
      'habitId',
      'effectiveFrom',
      'target',
      'minimumTarget',
      'enabled',
      'createdAt',
    });
    return HabitRevision(
      habitId: r.string('habitId', maxLength: _maxIdLength),
      effectiveFrom: r.date('effectiveFrom'),
      // The habit's type is checked against it by the validator.
      config: _config(r, null),
      createdAt: r.timestamp('createdAt'),
    );
  }

  /// A target and minimum within `1..target`, as every stored habit
  /// configuration has (the database enforces the same with CHECKs).
  static HabitConfig _config(_Obj o, HabitType? type) {
    final target = o.integer('target', min: 1, max: _maxValue);
    final minimum = o.integer('minimumTarget', min: 1, max: target);
    if (type == HabitType.binary && target != 1) {
      throw BackupFailure(
        BackupProblem.invalidData,
        '${o.path}.target: a done / not done habit has target 1',
      );
    }
    return HabitConfig(
      target: target,
      minimumTarget: minimum,
      enabled: o.boolean('enabled'),
    );
  }

  static const _maxIdLength = 64;
  static const _maxReflectionUnits = ReflectionRules.maxTextLength * 64;
  static const _maxValue = 100000;
}

/// A JSON object being read, with its position for error messages.
final class _Obj {
  _Obj(this._map, this.path);

  final Map<String, Object?> _map;
  final String path;

  static final _datePattern = RegExp(r'^\d{4}-\d{2}-\d{2}$');
  static final _timestampPattern = RegExp(
    r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d{1,6})?Z$',
  );
  static final _timePattern = RegExp(r'^(\d{2}):(\d{2})$');

  Never _fail(String key, String problem) =>
      throw BackupFailure(BackupProblem.invalidData, '$path.$key: $problem');

  /// Rejects any field not in [keys], and any missing one.
  void only(Set<String> keys) {
    for (final key in _map.keys) {
      // The name comes from the file, so it isn't repeated in the message.
      if (!keys.contains(key)) {
        throw BackupFailure(BackupProblem.invalidData, '$path: unknown field');
      }
    }
    for (final key in keys) {
      if (!_map.containsKey(key)) _fail(key, 'missing field');
    }
  }

  Object? _value(String key) {
    if (!_map.containsKey(key)) _fail(key, 'missing field');
    return _map[key];
  }

  String string(String key, {required int maxLength}) =>
      optString(key, maxLength: maxLength) ?? _fail(key, 'expected text');

  String? optString(String key, {required int maxLength}) {
    final v = _value(key);
    if (v == null) return null;
    if (v is! String || v.isEmpty) _fail(key, 'expected non-empty text');
    if (v.length > maxLength) _fail(key, 'text too long');
    return v;
  }

  int integer(String key, {int? min, int? max}) {
    final v = _value(key);
    if (v is! int) _fail(key, 'expected an integer');
    if ((min != null && v < min) || (max != null && v > max)) {
      _fail(key, 'integer out of range');
    }
    return v;
  }

  bool boolean(String key) {
    final v = _value(key);
    if (v is! bool) _fail(key, 'expected true or false');
    return v;
  }

  LocalDate date(String key) {
    final v = _value(key);
    if (v is! String || !_datePattern.hasMatch(v)) {
      _fail(key, 'expected a YYYY-MM-DD date');
    }
    try {
      return LocalDate.parse(v);
    } on ArgumentError {
      _fail(key, 'not a calendar date');
    }
  }

  DateTime timestamp(String key) =>
      optTimestamp(key) ?? _fail(key, 'expected a timestamp');

  /// An ISO-8601 UTC instant, returned in local time like every timestamp
  /// the app reads from storage.
  DateTime? optTimestamp(String key) {
    final v = _value(key);
    if (v == null) return null;
    if (v is! String || !_timestampPattern.hasMatch(v)) {
      _fail(key, 'expected an ISO-8601 UTC timestamp');
    }
    final parsed = DateTime.tryParse(v);
    if (parsed == null || parsed.year < 2000) _fail(key, 'not a valid time');
    return parsed.toLocal();
  }

  ReminderTime time(String key) {
    final v = _value(key);
    final match = v is String ? _timePattern.firstMatch(v) : null;
    if (match == null) _fail(key, 'expected HH:MM');
    final hour = int.parse(match.group(1)!);
    final minute = int.parse(match.group(2)!);
    if (hour > 23 || minute > 59) _fail(key, 'not a time of day');
    return ReminderTime(hour, minute);
  }

  /// The value of [values] whose [name] is the field's text.
  T choice<T>(String key, List<T> values, String Function(T) name) =>
      optChoice(key, values, name) ?? _fail(key, 'expected a value');

  T? optChoice<T>(String key, List<T> values, String Function(T) name) {
    final v = _value(key);
    if (v == null) return null;
    if (v is String) {
      for (final value in values) {
        if (name(value) == v) return value;
      }
    }
    _fail(key, 'unknown value');
  }

  _Obj object(String key) => optObject(key) ?? _fail(key, 'expected an object');

  _Obj? optObject(String key) {
    final v = _value(key);
    if (v == null) return null;
    if (v is! Map<String, Object?>) _fail(key, 'expected an object');
    return _Obj(v, '$path.$key');
  }

  List<_Obj> objects(String key) {
    final v = _value(key);
    if (v is! List<Object?>) _fail(key, 'expected a list');
    return [
      for (final (i, item) in v.indexed)
        if (item is Map<String, Object?>)
          _Obj(item, '$path.$key[$i]')
        else
          _fail('$key[$i]', 'expected an object'),
    ];
  }
}
