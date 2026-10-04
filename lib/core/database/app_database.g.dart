// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_database.dart';

// ignore_for_file: type=lint
class $WinterArcSessionsTable extends WinterArcSessions
    with TableInfo<$WinterArcSessionsTable, SessionRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $WinterArcSessionsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  @override
  late final GeneratedColumnWithTypeConverter<LocalDate, String> startDate =
      GeneratedColumn<String>(
        'start_date',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<LocalDate>($WinterArcSessionsTable.$converterstartDate);
  @override
  late final GeneratedColumnWithTypeConverter<LocalDate, String> endDate =
      GeneratedColumn<String>(
        'end_date',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<LocalDate>($WinterArcSessionsTable.$converterendDate);
  @override
  late final GeneratedColumnWithTypeConverter<WinterArcStatus, String> status =
      GeneratedColumn<String>(
        'status',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<WinterArcStatus>(
        $WinterArcSessionsTable.$converterstatus,
      );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _startedAtMeta = const VerificationMeta(
    'startedAt',
  );
  @override
  late final GeneratedColumn<DateTime> startedAt = GeneratedColumn<DateTime>(
    'started_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    startDate,
    endDate,
    status,
    createdAt,
    startedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'winter_arc_sessions';
  @override
  VerificationContext validateIntegrity(
    Insertable<SessionRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('started_at')) {
      context.handle(
        _startedAtMeta,
        startedAt.isAcceptableOrUnknown(data['started_at']!, _startedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  SessionRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SessionRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      startDate: $WinterArcSessionsTable.$converterstartDate.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}start_date'],
        )!,
      ),
      endDate: $WinterArcSessionsTable.$converterendDate.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}end_date'],
        )!,
      ),
      status: $WinterArcSessionsTable.$converterstatus.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}status'],
        )!,
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      startedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}started_at'],
      ),
    );
  }

  @override
  $WinterArcSessionsTable createAlias(String alias) {
    return $WinterArcSessionsTable(attachedDatabase, alias);
  }

  static TypeConverter<LocalDate, String> $converterstartDate =
      const LocalDateConverter();
  static TypeConverter<LocalDate, String> $converterendDate =
      const LocalDateConverter();
  static JsonTypeConverter2<WinterArcStatus, String, String> $converterstatus =
      const EnumNameConverter<WinterArcStatus>(WinterArcStatus.values);
}

class SessionRow extends DataClass implements Insertable<SessionRow> {
  final int id;
  final LocalDate startDate;
  final LocalDate endDate;
  final WinterArcStatus status;
  final DateTime createdAt;
  final DateTime? startedAt;
  const SessionRow({
    required this.id,
    required this.startDate,
    required this.endDate,
    required this.status,
    required this.createdAt,
    this.startedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    {
      map['start_date'] = Variable<String>(
        $WinterArcSessionsTable.$converterstartDate.toSql(startDate),
      );
    }
    {
      map['end_date'] = Variable<String>(
        $WinterArcSessionsTable.$converterendDate.toSql(endDate),
      );
    }
    {
      map['status'] = Variable<String>(
        $WinterArcSessionsTable.$converterstatus.toSql(status),
      );
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    if (!nullToAbsent || startedAt != null) {
      map['started_at'] = Variable<DateTime>(startedAt);
    }
    return map;
  }

  WinterArcSessionsCompanion toCompanion(bool nullToAbsent) {
    return WinterArcSessionsCompanion(
      id: Value(id),
      startDate: Value(startDate),
      endDate: Value(endDate),
      status: Value(status),
      createdAt: Value(createdAt),
      startedAt: startedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(startedAt),
    );
  }

  factory SessionRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SessionRow(
      id: serializer.fromJson<int>(json['id']),
      startDate: serializer.fromJson<LocalDate>(json['startDate']),
      endDate: serializer.fromJson<LocalDate>(json['endDate']),
      status: $WinterArcSessionsTable.$converterstatus.fromJson(
        serializer.fromJson<String>(json['status']),
      ),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      startedAt: serializer.fromJson<DateTime?>(json['startedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'startDate': serializer.toJson<LocalDate>(startDate),
      'endDate': serializer.toJson<LocalDate>(endDate),
      'status': serializer.toJson<String>(
        $WinterArcSessionsTable.$converterstatus.toJson(status),
      ),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'startedAt': serializer.toJson<DateTime?>(startedAt),
    };
  }

  SessionRow copyWith({
    int? id,
    LocalDate? startDate,
    LocalDate? endDate,
    WinterArcStatus? status,
    DateTime? createdAt,
    Value<DateTime?> startedAt = const Value.absent(),
  }) => SessionRow(
    id: id ?? this.id,
    startDate: startDate ?? this.startDate,
    endDate: endDate ?? this.endDate,
    status: status ?? this.status,
    createdAt: createdAt ?? this.createdAt,
    startedAt: startedAt.present ? startedAt.value : this.startedAt,
  );
  SessionRow copyWithCompanion(WinterArcSessionsCompanion data) {
    return SessionRow(
      id: data.id.present ? data.id.value : this.id,
      startDate: data.startDate.present ? data.startDate.value : this.startDate,
      endDate: data.endDate.present ? data.endDate.value : this.endDate,
      status: data.status.present ? data.status.value : this.status,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      startedAt: data.startedAt.present ? data.startedAt.value : this.startedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SessionRow(')
          ..write('id: $id, ')
          ..write('startDate: $startDate, ')
          ..write('endDate: $endDate, ')
          ..write('status: $status, ')
          ..write('createdAt: $createdAt, ')
          ..write('startedAt: $startedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, startDate, endDate, status, createdAt, startedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SessionRow &&
          other.id == this.id &&
          other.startDate == this.startDate &&
          other.endDate == this.endDate &&
          other.status == this.status &&
          other.createdAt == this.createdAt &&
          other.startedAt == this.startedAt);
}

class WinterArcSessionsCompanion extends UpdateCompanion<SessionRow> {
  final Value<int> id;
  final Value<LocalDate> startDate;
  final Value<LocalDate> endDate;
  final Value<WinterArcStatus> status;
  final Value<DateTime> createdAt;
  final Value<DateTime?> startedAt;
  const WinterArcSessionsCompanion({
    this.id = const Value.absent(),
    this.startDate = const Value.absent(),
    this.endDate = const Value.absent(),
    this.status = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.startedAt = const Value.absent(),
  });
  WinterArcSessionsCompanion.insert({
    this.id = const Value.absent(),
    required LocalDate startDate,
    required LocalDate endDate,
    required WinterArcStatus status,
    required DateTime createdAt,
    this.startedAt = const Value.absent(),
  }) : startDate = Value(startDate),
       endDate = Value(endDate),
       status = Value(status),
       createdAt = Value(createdAt);
  static Insertable<SessionRow> custom({
    Expression<int>? id,
    Expression<String>? startDate,
    Expression<String>? endDate,
    Expression<String>? status,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? startedAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (startDate != null) 'start_date': startDate,
      if (endDate != null) 'end_date': endDate,
      if (status != null) 'status': status,
      if (createdAt != null) 'created_at': createdAt,
      if (startedAt != null) 'started_at': startedAt,
    });
  }

  WinterArcSessionsCompanion copyWith({
    Value<int>? id,
    Value<LocalDate>? startDate,
    Value<LocalDate>? endDate,
    Value<WinterArcStatus>? status,
    Value<DateTime>? createdAt,
    Value<DateTime?>? startedAt,
  }) {
    return WinterArcSessionsCompanion(
      id: id ?? this.id,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      startedAt: startedAt ?? this.startedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (startDate.present) {
      map['start_date'] = Variable<String>(
        $WinterArcSessionsTable.$converterstartDate.toSql(startDate.value),
      );
    }
    if (endDate.present) {
      map['end_date'] = Variable<String>(
        $WinterArcSessionsTable.$converterendDate.toSql(endDate.value),
      );
    }
    if (status.present) {
      map['status'] = Variable<String>(
        $WinterArcSessionsTable.$converterstatus.toSql(status.value),
      );
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (startedAt.present) {
      map['started_at'] = Variable<DateTime>(startedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('WinterArcSessionsCompanion(')
          ..write('id: $id, ')
          ..write('startDate: $startDate, ')
          ..write('endDate: $endDate, ')
          ..write('status: $status, ')
          ..write('createdAt: $createdAt, ')
          ..write('startedAt: $startedAt')
          ..write(')'))
        .toString();
  }
}

class $HabitsTable extends Habits with TableInfo<$HabitsTable, HabitRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $HabitsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _sessionIdMeta = const VerificationMeta(
    'sessionId',
  );
  @override
  late final GeneratedColumn<int> sessionId = GeneratedColumn<int>(
    'session_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES winter_arc_sessions (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumnWithTypeConverter<HabitType, String> type =
      GeneratedColumn<String>(
        'type',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<HabitType>($HabitsTable.$convertertype);
  static const VerificationMeta _targetMeta = const VerificationMeta('target');
  @override
  late final GeneratedColumn<int> target = GeneratedColumn<int>(
    'target',
    aliasedName,
    false,
    check: () => ComparableExpr(target).isBiggerThanValue(0),
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _unitMeta = const VerificationMeta('unit');
  @override
  late final GeneratedColumn<String> unit = GeneratedColumn<String>(
    'unit',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _iconKeyMeta = const VerificationMeta(
    'iconKey',
  );
  @override
  late final GeneratedColumn<String> iconKey = GeneratedColumn<String>(
    'icon_key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _enabledMeta = const VerificationMeta(
    'enabled',
  );
  @override
  late final GeneratedColumn<bool> enabled = GeneratedColumn<bool>(
    'enabled',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("enabled" IN (0, 1))',
    ),
  );
  static const VerificationMeta _sortOrderMeta = const VerificationMeta(
    'sortOrder',
  );
  @override
  late final GeneratedColumn<int> sortOrder = GeneratedColumn<int>(
    'sort_order',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _minimumTargetMeta = const VerificationMeta(
    'minimumTarget',
  );
  @override
  late final GeneratedColumn<int> minimumTarget = GeneratedColumn<int>(
    'minimum_target',
    aliasedName,
    false,
    check: () =>
        ComparableExpr(minimumTarget).isBetween(const Constant(1), target),
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(1),
  );
  @override
  List<GeneratedColumn> get $columns => [
    sessionId,
    id,
    title,
    type,
    target,
    unit,
    iconKey,
    enabled,
    sortOrder,
    createdAt,
    minimumTarget,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'habits';
  @override
  VerificationContext validateIntegrity(
    Insertable<HabitRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('session_id')) {
      context.handle(
        _sessionIdMeta,
        sessionId.isAcceptableOrUnknown(data['session_id']!, _sessionIdMeta),
      );
    } else if (isInserting) {
      context.missing(_sessionIdMeta);
    }
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('target')) {
      context.handle(
        _targetMeta,
        target.isAcceptableOrUnknown(data['target']!, _targetMeta),
      );
    } else if (isInserting) {
      context.missing(_targetMeta);
    }
    if (data.containsKey('unit')) {
      context.handle(
        _unitMeta,
        unit.isAcceptableOrUnknown(data['unit']!, _unitMeta),
      );
    }
    if (data.containsKey('icon_key')) {
      context.handle(
        _iconKeyMeta,
        iconKey.isAcceptableOrUnknown(data['icon_key']!, _iconKeyMeta),
      );
    } else if (isInserting) {
      context.missing(_iconKeyMeta);
    }
    if (data.containsKey('enabled')) {
      context.handle(
        _enabledMeta,
        enabled.isAcceptableOrUnknown(data['enabled']!, _enabledMeta),
      );
    } else if (isInserting) {
      context.missing(_enabledMeta);
    }
    if (data.containsKey('sort_order')) {
      context.handle(
        _sortOrderMeta,
        sortOrder.isAcceptableOrUnknown(data['sort_order']!, _sortOrderMeta),
      );
    } else if (isInserting) {
      context.missing(_sortOrderMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('minimum_target')) {
      context.handle(
        _minimumTargetMeta,
        minimumTarget.isAcceptableOrUnknown(
          data['minimum_target']!,
          _minimumTargetMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {sessionId, id};
  @override
  HabitRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return HabitRow(
      sessionId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}session_id'],
      )!,
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      type: $HabitsTable.$convertertype.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}type'],
        )!,
      ),
      target: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}target'],
      )!,
      unit: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}unit'],
      ),
      iconKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}icon_key'],
      )!,
      enabled: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}enabled'],
      )!,
      sortOrder: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sort_order'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      minimumTarget: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}minimum_target'],
      )!,
    );
  }

  @override
  $HabitsTable createAlias(String alias) {
    return $HabitsTable(attachedDatabase, alias);
  }

  static JsonTypeConverter2<HabitType, String, String> $convertertype =
      const EnumNameConverter<HabitType>(HabitType.values);
}

class HabitRow extends DataClass implements Insertable<HabitRow> {
  final int sessionId;
  final String id;
  final String title;
  final HabitType type;
  final int target;
  final String? unit;
  final String iconKey;
  final bool enabled;
  final int sortOrder;
  final DateTime createdAt;

  /// Baseline Minimum Day target. Added in schema v2 (so it is the last
  /// column, as `ALTER TABLE ADD COLUMN` appends). The default only exists so
  /// the column can be added to existing rows; the v1 → v2 migration
  /// backfills real values.
  final int minimumTarget;
  const HabitRow({
    required this.sessionId,
    required this.id,
    required this.title,
    required this.type,
    required this.target,
    this.unit,
    required this.iconKey,
    required this.enabled,
    required this.sortOrder,
    required this.createdAt,
    required this.minimumTarget,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['session_id'] = Variable<int>(sessionId);
    map['id'] = Variable<String>(id);
    map['title'] = Variable<String>(title);
    {
      map['type'] = Variable<String>($HabitsTable.$convertertype.toSql(type));
    }
    map['target'] = Variable<int>(target);
    if (!nullToAbsent || unit != null) {
      map['unit'] = Variable<String>(unit);
    }
    map['icon_key'] = Variable<String>(iconKey);
    map['enabled'] = Variable<bool>(enabled);
    map['sort_order'] = Variable<int>(sortOrder);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['minimum_target'] = Variable<int>(minimumTarget);
    return map;
  }

  HabitsCompanion toCompanion(bool nullToAbsent) {
    return HabitsCompanion(
      sessionId: Value(sessionId),
      id: Value(id),
      title: Value(title),
      type: Value(type),
      target: Value(target),
      unit: unit == null && nullToAbsent ? const Value.absent() : Value(unit),
      iconKey: Value(iconKey),
      enabled: Value(enabled),
      sortOrder: Value(sortOrder),
      createdAt: Value(createdAt),
      minimumTarget: Value(minimumTarget),
    );
  }

  factory HabitRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return HabitRow(
      sessionId: serializer.fromJson<int>(json['sessionId']),
      id: serializer.fromJson<String>(json['id']),
      title: serializer.fromJson<String>(json['title']),
      type: $HabitsTable.$convertertype.fromJson(
        serializer.fromJson<String>(json['type']),
      ),
      target: serializer.fromJson<int>(json['target']),
      unit: serializer.fromJson<String?>(json['unit']),
      iconKey: serializer.fromJson<String>(json['iconKey']),
      enabled: serializer.fromJson<bool>(json['enabled']),
      sortOrder: serializer.fromJson<int>(json['sortOrder']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      minimumTarget: serializer.fromJson<int>(json['minimumTarget']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'sessionId': serializer.toJson<int>(sessionId),
      'id': serializer.toJson<String>(id),
      'title': serializer.toJson<String>(title),
      'type': serializer.toJson<String>(
        $HabitsTable.$convertertype.toJson(type),
      ),
      'target': serializer.toJson<int>(target),
      'unit': serializer.toJson<String?>(unit),
      'iconKey': serializer.toJson<String>(iconKey),
      'enabled': serializer.toJson<bool>(enabled),
      'sortOrder': serializer.toJson<int>(sortOrder),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'minimumTarget': serializer.toJson<int>(minimumTarget),
    };
  }

  HabitRow copyWith({
    int? sessionId,
    String? id,
    String? title,
    HabitType? type,
    int? target,
    Value<String?> unit = const Value.absent(),
    String? iconKey,
    bool? enabled,
    int? sortOrder,
    DateTime? createdAt,
    int? minimumTarget,
  }) => HabitRow(
    sessionId: sessionId ?? this.sessionId,
    id: id ?? this.id,
    title: title ?? this.title,
    type: type ?? this.type,
    target: target ?? this.target,
    unit: unit.present ? unit.value : this.unit,
    iconKey: iconKey ?? this.iconKey,
    enabled: enabled ?? this.enabled,
    sortOrder: sortOrder ?? this.sortOrder,
    createdAt: createdAt ?? this.createdAt,
    minimumTarget: minimumTarget ?? this.minimumTarget,
  );
  HabitRow copyWithCompanion(HabitsCompanion data) {
    return HabitRow(
      sessionId: data.sessionId.present ? data.sessionId.value : this.sessionId,
      id: data.id.present ? data.id.value : this.id,
      title: data.title.present ? data.title.value : this.title,
      type: data.type.present ? data.type.value : this.type,
      target: data.target.present ? data.target.value : this.target,
      unit: data.unit.present ? data.unit.value : this.unit,
      iconKey: data.iconKey.present ? data.iconKey.value : this.iconKey,
      enabled: data.enabled.present ? data.enabled.value : this.enabled,
      sortOrder: data.sortOrder.present ? data.sortOrder.value : this.sortOrder,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      minimumTarget: data.minimumTarget.present
          ? data.minimumTarget.value
          : this.minimumTarget,
    );
  }

  @override
  String toString() {
    return (StringBuffer('HabitRow(')
          ..write('sessionId: $sessionId, ')
          ..write('id: $id, ')
          ..write('title: $title, ')
          ..write('type: $type, ')
          ..write('target: $target, ')
          ..write('unit: $unit, ')
          ..write('iconKey: $iconKey, ')
          ..write('enabled: $enabled, ')
          ..write('sortOrder: $sortOrder, ')
          ..write('createdAt: $createdAt, ')
          ..write('minimumTarget: $minimumTarget')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    sessionId,
    id,
    title,
    type,
    target,
    unit,
    iconKey,
    enabled,
    sortOrder,
    createdAt,
    minimumTarget,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is HabitRow &&
          other.sessionId == this.sessionId &&
          other.id == this.id &&
          other.title == this.title &&
          other.type == this.type &&
          other.target == this.target &&
          other.unit == this.unit &&
          other.iconKey == this.iconKey &&
          other.enabled == this.enabled &&
          other.sortOrder == this.sortOrder &&
          other.createdAt == this.createdAt &&
          other.minimumTarget == this.minimumTarget);
}

class HabitsCompanion extends UpdateCompanion<HabitRow> {
  final Value<int> sessionId;
  final Value<String> id;
  final Value<String> title;
  final Value<HabitType> type;
  final Value<int> target;
  final Value<String?> unit;
  final Value<String> iconKey;
  final Value<bool> enabled;
  final Value<int> sortOrder;
  final Value<DateTime> createdAt;
  final Value<int> minimumTarget;
  final Value<int> rowid;
  const HabitsCompanion({
    this.sessionId = const Value.absent(),
    this.id = const Value.absent(),
    this.title = const Value.absent(),
    this.type = const Value.absent(),
    this.target = const Value.absent(),
    this.unit = const Value.absent(),
    this.iconKey = const Value.absent(),
    this.enabled = const Value.absent(),
    this.sortOrder = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.minimumTarget = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  HabitsCompanion.insert({
    required int sessionId,
    required String id,
    required String title,
    required HabitType type,
    required int target,
    this.unit = const Value.absent(),
    required String iconKey,
    required bool enabled,
    required int sortOrder,
    required DateTime createdAt,
    this.minimumTarget = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : sessionId = Value(sessionId),
       id = Value(id),
       title = Value(title),
       type = Value(type),
       target = Value(target),
       iconKey = Value(iconKey),
       enabled = Value(enabled),
       sortOrder = Value(sortOrder),
       createdAt = Value(createdAt);
  static Insertable<HabitRow> custom({
    Expression<int>? sessionId,
    Expression<String>? id,
    Expression<String>? title,
    Expression<String>? type,
    Expression<int>? target,
    Expression<String>? unit,
    Expression<String>? iconKey,
    Expression<bool>? enabled,
    Expression<int>? sortOrder,
    Expression<DateTime>? createdAt,
    Expression<int>? minimumTarget,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (sessionId != null) 'session_id': sessionId,
      if (id != null) 'id': id,
      if (title != null) 'title': title,
      if (type != null) 'type': type,
      if (target != null) 'target': target,
      if (unit != null) 'unit': unit,
      if (iconKey != null) 'icon_key': iconKey,
      if (enabled != null) 'enabled': enabled,
      if (sortOrder != null) 'sort_order': sortOrder,
      if (createdAt != null) 'created_at': createdAt,
      if (minimumTarget != null) 'minimum_target': minimumTarget,
      if (rowid != null) 'rowid': rowid,
    });
  }

  HabitsCompanion copyWith({
    Value<int>? sessionId,
    Value<String>? id,
    Value<String>? title,
    Value<HabitType>? type,
    Value<int>? target,
    Value<String?>? unit,
    Value<String>? iconKey,
    Value<bool>? enabled,
    Value<int>? sortOrder,
    Value<DateTime>? createdAt,
    Value<int>? minimumTarget,
    Value<int>? rowid,
  }) {
    return HabitsCompanion(
      sessionId: sessionId ?? this.sessionId,
      id: id ?? this.id,
      title: title ?? this.title,
      type: type ?? this.type,
      target: target ?? this.target,
      unit: unit ?? this.unit,
      iconKey: iconKey ?? this.iconKey,
      enabled: enabled ?? this.enabled,
      sortOrder: sortOrder ?? this.sortOrder,
      createdAt: createdAt ?? this.createdAt,
      minimumTarget: minimumTarget ?? this.minimumTarget,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (sessionId.present) {
      map['session_id'] = Variable<int>(sessionId.value);
    }
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (type.present) {
      map['type'] = Variable<String>(
        $HabitsTable.$convertertype.toSql(type.value),
      );
    }
    if (target.present) {
      map['target'] = Variable<int>(target.value);
    }
    if (unit.present) {
      map['unit'] = Variable<String>(unit.value);
    }
    if (iconKey.present) {
      map['icon_key'] = Variable<String>(iconKey.value);
    }
    if (enabled.present) {
      map['enabled'] = Variable<bool>(enabled.value);
    }
    if (sortOrder.present) {
      map['sort_order'] = Variable<int>(sortOrder.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (minimumTarget.present) {
      map['minimum_target'] = Variable<int>(minimumTarget.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('HabitsCompanion(')
          ..write('sessionId: $sessionId, ')
          ..write('id: $id, ')
          ..write('title: $title, ')
          ..write('type: $type, ')
          ..write('target: $target, ')
          ..write('unit: $unit, ')
          ..write('iconKey: $iconKey, ')
          ..write('enabled: $enabled, ')
          ..write('sortOrder: $sortOrder, ')
          ..write('createdAt: $createdAt, ')
          ..write('minimumTarget: $minimumTarget, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $DailyHabitProgressEntriesTable extends DailyHabitProgressEntries
    with TableInfo<$DailyHabitProgressEntriesTable, HabitProgressRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $DailyHabitProgressEntriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _sessionIdMeta = const VerificationMeta(
    'sessionId',
  );
  @override
  late final GeneratedColumn<int> sessionId = GeneratedColumn<int>(
    'session_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _habitIdMeta = const VerificationMeta(
    'habitId',
  );
  @override
  late final GeneratedColumn<String> habitId = GeneratedColumn<String>(
    'habit_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumnWithTypeConverter<LocalDate, String> date =
      GeneratedColumn<String>(
        'date',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<LocalDate>(
        $DailyHabitProgressEntriesTable.$converterdate,
      );
  static const VerificationMeta _currentValueMeta = const VerificationMeta(
    'currentValue',
  );
  @override
  late final GeneratedColumn<int> currentValue = GeneratedColumn<int>(
    'current_value',
    aliasedName,
    false,
    check: () => ComparableExpr(currentValue).isBiggerOrEqualValue(0),
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _completedMeta = const VerificationMeta(
    'completed',
  );
  @override
  late final GeneratedColumn<bool> completed = GeneratedColumn<bool>(
    'completed',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("completed" IN (0, 1))',
    ),
  );
  static const VerificationMeta _completedAtMeta = const VerificationMeta(
    'completedAt',
  );
  @override
  late final GeneratedColumn<DateTime> completedAt = GeneratedColumn<DateTime>(
    'completed_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    sessionId,
    habitId,
    date,
    currentValue,
    completed,
    completedAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'daily_habit_progress_entries';
  @override
  VerificationContext validateIntegrity(
    Insertable<HabitProgressRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('session_id')) {
      context.handle(
        _sessionIdMeta,
        sessionId.isAcceptableOrUnknown(data['session_id']!, _sessionIdMeta),
      );
    } else if (isInserting) {
      context.missing(_sessionIdMeta);
    }
    if (data.containsKey('habit_id')) {
      context.handle(
        _habitIdMeta,
        habitId.isAcceptableOrUnknown(data['habit_id']!, _habitIdMeta),
      );
    } else if (isInserting) {
      context.missing(_habitIdMeta);
    }
    if (data.containsKey('current_value')) {
      context.handle(
        _currentValueMeta,
        currentValue.isAcceptableOrUnknown(
          data['current_value']!,
          _currentValueMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_currentValueMeta);
    }
    if (data.containsKey('completed')) {
      context.handle(
        _completedMeta,
        completed.isAcceptableOrUnknown(data['completed']!, _completedMeta),
      );
    } else if (isInserting) {
      context.missing(_completedMeta);
    }
    if (data.containsKey('completed_at')) {
      context.handle(
        _completedAtMeta,
        completedAt.isAcceptableOrUnknown(
          data['completed_at']!,
          _completedAtMeta,
        ),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {sessionId, habitId, date};
  @override
  HabitProgressRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return HabitProgressRow(
      sessionId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}session_id'],
      )!,
      habitId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}habit_id'],
      )!,
      date: $DailyHabitProgressEntriesTable.$converterdate.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}date'],
        )!,
      ),
      currentValue: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}current_value'],
      )!,
      completed: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}completed'],
      )!,
      completedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}completed_at'],
      ),
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $DailyHabitProgressEntriesTable createAlias(String alias) {
    return $DailyHabitProgressEntriesTable(attachedDatabase, alias);
  }

  static TypeConverter<LocalDate, String> $converterdate =
      const LocalDateConverter();
}

class HabitProgressRow extends DataClass
    implements Insertable<HabitProgressRow> {
  final int sessionId;
  final String habitId;
  final LocalDate date;
  final int currentValue;
  final bool completed;
  final DateTime? completedAt;
  final DateTime updatedAt;
  const HabitProgressRow({
    required this.sessionId,
    required this.habitId,
    required this.date,
    required this.currentValue,
    required this.completed,
    this.completedAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['session_id'] = Variable<int>(sessionId);
    map['habit_id'] = Variable<String>(habitId);
    {
      map['date'] = Variable<String>(
        $DailyHabitProgressEntriesTable.$converterdate.toSql(date),
      );
    }
    map['current_value'] = Variable<int>(currentValue);
    map['completed'] = Variable<bool>(completed);
    if (!nullToAbsent || completedAt != null) {
      map['completed_at'] = Variable<DateTime>(completedAt);
    }
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  DailyHabitProgressEntriesCompanion toCompanion(bool nullToAbsent) {
    return DailyHabitProgressEntriesCompanion(
      sessionId: Value(sessionId),
      habitId: Value(habitId),
      date: Value(date),
      currentValue: Value(currentValue),
      completed: Value(completed),
      completedAt: completedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(completedAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory HabitProgressRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return HabitProgressRow(
      sessionId: serializer.fromJson<int>(json['sessionId']),
      habitId: serializer.fromJson<String>(json['habitId']),
      date: serializer.fromJson<LocalDate>(json['date']),
      currentValue: serializer.fromJson<int>(json['currentValue']),
      completed: serializer.fromJson<bool>(json['completed']),
      completedAt: serializer.fromJson<DateTime?>(json['completedAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'sessionId': serializer.toJson<int>(sessionId),
      'habitId': serializer.toJson<String>(habitId),
      'date': serializer.toJson<LocalDate>(date),
      'currentValue': serializer.toJson<int>(currentValue),
      'completed': serializer.toJson<bool>(completed),
      'completedAt': serializer.toJson<DateTime?>(completedAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  HabitProgressRow copyWith({
    int? sessionId,
    String? habitId,
    LocalDate? date,
    int? currentValue,
    bool? completed,
    Value<DateTime?> completedAt = const Value.absent(),
    DateTime? updatedAt,
  }) => HabitProgressRow(
    sessionId: sessionId ?? this.sessionId,
    habitId: habitId ?? this.habitId,
    date: date ?? this.date,
    currentValue: currentValue ?? this.currentValue,
    completed: completed ?? this.completed,
    completedAt: completedAt.present ? completedAt.value : this.completedAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  HabitProgressRow copyWithCompanion(DailyHabitProgressEntriesCompanion data) {
    return HabitProgressRow(
      sessionId: data.sessionId.present ? data.sessionId.value : this.sessionId,
      habitId: data.habitId.present ? data.habitId.value : this.habitId,
      date: data.date.present ? data.date.value : this.date,
      currentValue: data.currentValue.present
          ? data.currentValue.value
          : this.currentValue,
      completed: data.completed.present ? data.completed.value : this.completed,
      completedAt: data.completedAt.present
          ? data.completedAt.value
          : this.completedAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('HabitProgressRow(')
          ..write('sessionId: $sessionId, ')
          ..write('habitId: $habitId, ')
          ..write('date: $date, ')
          ..write('currentValue: $currentValue, ')
          ..write('completed: $completed, ')
          ..write('completedAt: $completedAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    sessionId,
    habitId,
    date,
    currentValue,
    completed,
    completedAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is HabitProgressRow &&
          other.sessionId == this.sessionId &&
          other.habitId == this.habitId &&
          other.date == this.date &&
          other.currentValue == this.currentValue &&
          other.completed == this.completed &&
          other.completedAt == this.completedAt &&
          other.updatedAt == this.updatedAt);
}

class DailyHabitProgressEntriesCompanion
    extends UpdateCompanion<HabitProgressRow> {
  final Value<int> sessionId;
  final Value<String> habitId;
  final Value<LocalDate> date;
  final Value<int> currentValue;
  final Value<bool> completed;
  final Value<DateTime?> completedAt;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const DailyHabitProgressEntriesCompanion({
    this.sessionId = const Value.absent(),
    this.habitId = const Value.absent(),
    this.date = const Value.absent(),
    this.currentValue = const Value.absent(),
    this.completed = const Value.absent(),
    this.completedAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  DailyHabitProgressEntriesCompanion.insert({
    required int sessionId,
    required String habitId,
    required LocalDate date,
    required int currentValue,
    required bool completed,
    this.completedAt = const Value.absent(),
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  }) : sessionId = Value(sessionId),
       habitId = Value(habitId),
       date = Value(date),
       currentValue = Value(currentValue),
       completed = Value(completed),
       updatedAt = Value(updatedAt);
  static Insertable<HabitProgressRow> custom({
    Expression<int>? sessionId,
    Expression<String>? habitId,
    Expression<String>? date,
    Expression<int>? currentValue,
    Expression<bool>? completed,
    Expression<DateTime>? completedAt,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (sessionId != null) 'session_id': sessionId,
      if (habitId != null) 'habit_id': habitId,
      if (date != null) 'date': date,
      if (currentValue != null) 'current_value': currentValue,
      if (completed != null) 'completed': completed,
      if (completedAt != null) 'completed_at': completedAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  DailyHabitProgressEntriesCompanion copyWith({
    Value<int>? sessionId,
    Value<String>? habitId,
    Value<LocalDate>? date,
    Value<int>? currentValue,
    Value<bool>? completed,
    Value<DateTime?>? completedAt,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return DailyHabitProgressEntriesCompanion(
      sessionId: sessionId ?? this.sessionId,
      habitId: habitId ?? this.habitId,
      date: date ?? this.date,
      currentValue: currentValue ?? this.currentValue,
      completed: completed ?? this.completed,
      completedAt: completedAt ?? this.completedAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (sessionId.present) {
      map['session_id'] = Variable<int>(sessionId.value);
    }
    if (habitId.present) {
      map['habit_id'] = Variable<String>(habitId.value);
    }
    if (date.present) {
      map['date'] = Variable<String>(
        $DailyHabitProgressEntriesTable.$converterdate.toSql(date.value),
      );
    }
    if (currentValue.present) {
      map['current_value'] = Variable<int>(currentValue.value);
    }
    if (completed.present) {
      map['completed'] = Variable<bool>(completed.value);
    }
    if (completedAt.present) {
      map['completed_at'] = Variable<DateTime>(completedAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('DailyHabitProgressEntriesCompanion(')
          ..write('sessionId: $sessionId, ')
          ..write('habitId: $habitId, ')
          ..write('date: $date, ')
          ..write('currentValue: $currentValue, ')
          ..write('completed: $completed, ')
          ..write('completedAt: $completedAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $XpTransactionsTable extends XpTransactions
    with TableInfo<$XpTransactionsTable, XpTransactionRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $XpTransactionsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _sessionIdMeta = const VerificationMeta(
    'sessionId',
  );
  @override
  late final GeneratedColumn<int> sessionId = GeneratedColumn<int>(
    'session_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES winter_arc_sessions (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _sourceKeyMeta = const VerificationMeta(
    'sourceKey',
  );
  @override
  late final GeneratedColumn<String> sourceKey = GeneratedColumn<String>(
    'source_key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumnWithTypeConverter<XpReason, String> reason =
      GeneratedColumn<String>(
        'reason',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<XpReason>($XpTransactionsTable.$converterreason);
  static const VerificationMeta _amountMeta = const VerificationMeta('amount');
  @override
  late final GeneratedColumn<int> amount = GeneratedColumn<int>(
    'amount',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _habitIdMeta = const VerificationMeta(
    'habitId',
  );
  @override
  late final GeneratedColumn<String> habitId = GeneratedColumn<String>(
    'habit_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  late final GeneratedColumnWithTypeConverter<LocalDate, String> date =
      GeneratedColumn<String>(
        'date',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<LocalDate>($XpTransactionsTable.$converterdate);
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    sessionId,
    sourceKey,
    reason,
    amount,
    habitId,
    date,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'xp_transactions';
  @override
  VerificationContext validateIntegrity(
    Insertable<XpTransactionRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('session_id')) {
      context.handle(
        _sessionIdMeta,
        sessionId.isAcceptableOrUnknown(data['session_id']!, _sessionIdMeta),
      );
    } else if (isInserting) {
      context.missing(_sessionIdMeta);
    }
    if (data.containsKey('source_key')) {
      context.handle(
        _sourceKeyMeta,
        sourceKey.isAcceptableOrUnknown(data['source_key']!, _sourceKeyMeta),
      );
    } else if (isInserting) {
      context.missing(_sourceKeyMeta);
    }
    if (data.containsKey('amount')) {
      context.handle(
        _amountMeta,
        amount.isAcceptableOrUnknown(data['amount']!, _amountMeta),
      );
    } else if (isInserting) {
      context.missing(_amountMeta);
    }
    if (data.containsKey('habit_id')) {
      context.handle(
        _habitIdMeta,
        habitId.isAcceptableOrUnknown(data['habit_id']!, _habitIdMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [
    {sessionId, sourceKey},
  ];
  @override
  XpTransactionRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return XpTransactionRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      sessionId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}session_id'],
      )!,
      sourceKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source_key'],
      )!,
      reason: $XpTransactionsTable.$converterreason.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}reason'],
        )!,
      ),
      amount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}amount'],
      )!,
      habitId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}habit_id'],
      ),
      date: $XpTransactionsTable.$converterdate.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}date'],
        )!,
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $XpTransactionsTable createAlias(String alias) {
    return $XpTransactionsTable(attachedDatabase, alias);
  }

  static JsonTypeConverter2<XpReason, String, String> $converterreason =
      const EnumNameConverter<XpReason>(XpReason.values);
  static TypeConverter<LocalDate, String> $converterdate =
      const LocalDateConverter();
}

class XpTransactionRow extends DataClass
    implements Insertable<XpTransactionRow> {
  final int id;
  final int sessionId;

  /// Idempotency key, see `XpRules.habitCompletionKey`.
  final String sourceKey;
  final XpReason reason;
  final int amount;
  final String? habitId;
  final LocalDate date;
  final DateTime createdAt;
  const XpTransactionRow({
    required this.id,
    required this.sessionId,
    required this.sourceKey,
    required this.reason,
    required this.amount,
    this.habitId,
    required this.date,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['session_id'] = Variable<int>(sessionId);
    map['source_key'] = Variable<String>(sourceKey);
    {
      map['reason'] = Variable<String>(
        $XpTransactionsTable.$converterreason.toSql(reason),
      );
    }
    map['amount'] = Variable<int>(amount);
    if (!nullToAbsent || habitId != null) {
      map['habit_id'] = Variable<String>(habitId);
    }
    {
      map['date'] = Variable<String>(
        $XpTransactionsTable.$converterdate.toSql(date),
      );
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  XpTransactionsCompanion toCompanion(bool nullToAbsent) {
    return XpTransactionsCompanion(
      id: Value(id),
      sessionId: Value(sessionId),
      sourceKey: Value(sourceKey),
      reason: Value(reason),
      amount: Value(amount),
      habitId: habitId == null && nullToAbsent
          ? const Value.absent()
          : Value(habitId),
      date: Value(date),
      createdAt: Value(createdAt),
    );
  }

  factory XpTransactionRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return XpTransactionRow(
      id: serializer.fromJson<int>(json['id']),
      sessionId: serializer.fromJson<int>(json['sessionId']),
      sourceKey: serializer.fromJson<String>(json['sourceKey']),
      reason: $XpTransactionsTable.$converterreason.fromJson(
        serializer.fromJson<String>(json['reason']),
      ),
      amount: serializer.fromJson<int>(json['amount']),
      habitId: serializer.fromJson<String?>(json['habitId']),
      date: serializer.fromJson<LocalDate>(json['date']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'sessionId': serializer.toJson<int>(sessionId),
      'sourceKey': serializer.toJson<String>(sourceKey),
      'reason': serializer.toJson<String>(
        $XpTransactionsTable.$converterreason.toJson(reason),
      ),
      'amount': serializer.toJson<int>(amount),
      'habitId': serializer.toJson<String?>(habitId),
      'date': serializer.toJson<LocalDate>(date),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  XpTransactionRow copyWith({
    int? id,
    int? sessionId,
    String? sourceKey,
    XpReason? reason,
    int? amount,
    Value<String?> habitId = const Value.absent(),
    LocalDate? date,
    DateTime? createdAt,
  }) => XpTransactionRow(
    id: id ?? this.id,
    sessionId: sessionId ?? this.sessionId,
    sourceKey: sourceKey ?? this.sourceKey,
    reason: reason ?? this.reason,
    amount: amount ?? this.amount,
    habitId: habitId.present ? habitId.value : this.habitId,
    date: date ?? this.date,
    createdAt: createdAt ?? this.createdAt,
  );
  XpTransactionRow copyWithCompanion(XpTransactionsCompanion data) {
    return XpTransactionRow(
      id: data.id.present ? data.id.value : this.id,
      sessionId: data.sessionId.present ? data.sessionId.value : this.sessionId,
      sourceKey: data.sourceKey.present ? data.sourceKey.value : this.sourceKey,
      reason: data.reason.present ? data.reason.value : this.reason,
      amount: data.amount.present ? data.amount.value : this.amount,
      habitId: data.habitId.present ? data.habitId.value : this.habitId,
      date: data.date.present ? data.date.value : this.date,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('XpTransactionRow(')
          ..write('id: $id, ')
          ..write('sessionId: $sessionId, ')
          ..write('sourceKey: $sourceKey, ')
          ..write('reason: $reason, ')
          ..write('amount: $amount, ')
          ..write('habitId: $habitId, ')
          ..write('date: $date, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    sessionId,
    sourceKey,
    reason,
    amount,
    habitId,
    date,
    createdAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is XpTransactionRow &&
          other.id == this.id &&
          other.sessionId == this.sessionId &&
          other.sourceKey == this.sourceKey &&
          other.reason == this.reason &&
          other.amount == this.amount &&
          other.habitId == this.habitId &&
          other.date == this.date &&
          other.createdAt == this.createdAt);
}

class XpTransactionsCompanion extends UpdateCompanion<XpTransactionRow> {
  final Value<int> id;
  final Value<int> sessionId;
  final Value<String> sourceKey;
  final Value<XpReason> reason;
  final Value<int> amount;
  final Value<String?> habitId;
  final Value<LocalDate> date;
  final Value<DateTime> createdAt;
  const XpTransactionsCompanion({
    this.id = const Value.absent(),
    this.sessionId = const Value.absent(),
    this.sourceKey = const Value.absent(),
    this.reason = const Value.absent(),
    this.amount = const Value.absent(),
    this.habitId = const Value.absent(),
    this.date = const Value.absent(),
    this.createdAt = const Value.absent(),
  });
  XpTransactionsCompanion.insert({
    this.id = const Value.absent(),
    required int sessionId,
    required String sourceKey,
    required XpReason reason,
    required int amount,
    this.habitId = const Value.absent(),
    required LocalDate date,
    required DateTime createdAt,
  }) : sessionId = Value(sessionId),
       sourceKey = Value(sourceKey),
       reason = Value(reason),
       amount = Value(amount),
       date = Value(date),
       createdAt = Value(createdAt);
  static Insertable<XpTransactionRow> custom({
    Expression<int>? id,
    Expression<int>? sessionId,
    Expression<String>? sourceKey,
    Expression<String>? reason,
    Expression<int>? amount,
    Expression<String>? habitId,
    Expression<String>? date,
    Expression<DateTime>? createdAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (sessionId != null) 'session_id': sessionId,
      if (sourceKey != null) 'source_key': sourceKey,
      if (reason != null) 'reason': reason,
      if (amount != null) 'amount': amount,
      if (habitId != null) 'habit_id': habitId,
      if (date != null) 'date': date,
      if (createdAt != null) 'created_at': createdAt,
    });
  }

  XpTransactionsCompanion copyWith({
    Value<int>? id,
    Value<int>? sessionId,
    Value<String>? sourceKey,
    Value<XpReason>? reason,
    Value<int>? amount,
    Value<String?>? habitId,
    Value<LocalDate>? date,
    Value<DateTime>? createdAt,
  }) {
    return XpTransactionsCompanion(
      id: id ?? this.id,
      sessionId: sessionId ?? this.sessionId,
      sourceKey: sourceKey ?? this.sourceKey,
      reason: reason ?? this.reason,
      amount: amount ?? this.amount,
      habitId: habitId ?? this.habitId,
      date: date ?? this.date,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (sessionId.present) {
      map['session_id'] = Variable<int>(sessionId.value);
    }
    if (sourceKey.present) {
      map['source_key'] = Variable<String>(sourceKey.value);
    }
    if (reason.present) {
      map['reason'] = Variable<String>(
        $XpTransactionsTable.$converterreason.toSql(reason.value),
      );
    }
    if (amount.present) {
      map['amount'] = Variable<int>(amount.value);
    }
    if (habitId.present) {
      map['habit_id'] = Variable<String>(habitId.value);
    }
    if (date.present) {
      map['date'] = Variable<String>(
        $XpTransactionsTable.$converterdate.toSql(date.value),
      );
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('XpTransactionsCompanion(')
          ..write('id: $id, ')
          ..write('sessionId: $sessionId, ')
          ..write('sourceKey: $sourceKey, ')
          ..write('reason: $reason, ')
          ..write('amount: $amount, ')
          ..write('habitId: $habitId, ')
          ..write('date: $date, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }
}

class $HabitRevisionsTable extends HabitRevisions
    with TableInfo<$HabitRevisionsTable, HabitRevisionRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $HabitRevisionsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _sessionIdMeta = const VerificationMeta(
    'sessionId',
  );
  @override
  late final GeneratedColumn<int> sessionId = GeneratedColumn<int>(
    'session_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _habitIdMeta = const VerificationMeta(
    'habitId',
  );
  @override
  late final GeneratedColumn<String> habitId = GeneratedColumn<String>(
    'habit_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumnWithTypeConverter<LocalDate, String> effectiveFrom =
      GeneratedColumn<String>(
        'effective_from',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<LocalDate>($HabitRevisionsTable.$convertereffectiveFrom);
  static const VerificationMeta _targetMeta = const VerificationMeta('target');
  @override
  late final GeneratedColumn<int> target = GeneratedColumn<int>(
    'target',
    aliasedName,
    false,
    check: () => ComparableExpr(target).isBiggerThanValue(0),
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _minimumTargetMeta = const VerificationMeta(
    'minimumTarget',
  );
  @override
  late final GeneratedColumn<int> minimumTarget = GeneratedColumn<int>(
    'minimum_target',
    aliasedName,
    false,
    check: () =>
        ComparableExpr(minimumTarget).isBetween(const Constant(1), target),
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _enabledMeta = const VerificationMeta(
    'enabled',
  );
  @override
  late final GeneratedColumn<bool> enabled = GeneratedColumn<bool>(
    'enabled',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("enabled" IN (0, 1))',
    ),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    sessionId,
    habitId,
    effectiveFrom,
    target,
    minimumTarget,
    enabled,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'habit_revisions';
  @override
  VerificationContext validateIntegrity(
    Insertable<HabitRevisionRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('session_id')) {
      context.handle(
        _sessionIdMeta,
        sessionId.isAcceptableOrUnknown(data['session_id']!, _sessionIdMeta),
      );
    } else if (isInserting) {
      context.missing(_sessionIdMeta);
    }
    if (data.containsKey('habit_id')) {
      context.handle(
        _habitIdMeta,
        habitId.isAcceptableOrUnknown(data['habit_id']!, _habitIdMeta),
      );
    } else if (isInserting) {
      context.missing(_habitIdMeta);
    }
    if (data.containsKey('target')) {
      context.handle(
        _targetMeta,
        target.isAcceptableOrUnknown(data['target']!, _targetMeta),
      );
    } else if (isInserting) {
      context.missing(_targetMeta);
    }
    if (data.containsKey('minimum_target')) {
      context.handle(
        _minimumTargetMeta,
        minimumTarget.isAcceptableOrUnknown(
          data['minimum_target']!,
          _minimumTargetMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_minimumTargetMeta);
    }
    if (data.containsKey('enabled')) {
      context.handle(
        _enabledMeta,
        enabled.isAcceptableOrUnknown(data['enabled']!, _enabledMeta),
      );
    } else if (isInserting) {
      context.missing(_enabledMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {sessionId, habitId, effectiveFrom};
  @override
  HabitRevisionRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return HabitRevisionRow(
      sessionId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}session_id'],
      )!,
      habitId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}habit_id'],
      )!,
      effectiveFrom: $HabitRevisionsTable.$convertereffectiveFrom.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}effective_from'],
        )!,
      ),
      target: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}target'],
      )!,
      minimumTarget: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}minimum_target'],
      )!,
      enabled: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}enabled'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $HabitRevisionsTable createAlias(String alias) {
    return $HabitRevisionsTable(attachedDatabase, alias);
  }

  static TypeConverter<LocalDate, String> $convertereffectiveFrom =
      const LocalDateConverter();
}

class HabitRevisionRow extends DataClass
    implements Insertable<HabitRevisionRow> {
  final int sessionId;
  final String habitId;
  final LocalDate effectiveFrom;
  final int target;
  final int minimumTarget;
  final bool enabled;
  final DateTime createdAt;
  const HabitRevisionRow({
    required this.sessionId,
    required this.habitId,
    required this.effectiveFrom,
    required this.target,
    required this.minimumTarget,
    required this.enabled,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['session_id'] = Variable<int>(sessionId);
    map['habit_id'] = Variable<String>(habitId);
    {
      map['effective_from'] = Variable<String>(
        $HabitRevisionsTable.$convertereffectiveFrom.toSql(effectiveFrom),
      );
    }
    map['target'] = Variable<int>(target);
    map['minimum_target'] = Variable<int>(minimumTarget);
    map['enabled'] = Variable<bool>(enabled);
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  HabitRevisionsCompanion toCompanion(bool nullToAbsent) {
    return HabitRevisionsCompanion(
      sessionId: Value(sessionId),
      habitId: Value(habitId),
      effectiveFrom: Value(effectiveFrom),
      target: Value(target),
      minimumTarget: Value(minimumTarget),
      enabled: Value(enabled),
      createdAt: Value(createdAt),
    );
  }

  factory HabitRevisionRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return HabitRevisionRow(
      sessionId: serializer.fromJson<int>(json['sessionId']),
      habitId: serializer.fromJson<String>(json['habitId']),
      effectiveFrom: serializer.fromJson<LocalDate>(json['effectiveFrom']),
      target: serializer.fromJson<int>(json['target']),
      minimumTarget: serializer.fromJson<int>(json['minimumTarget']),
      enabled: serializer.fromJson<bool>(json['enabled']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'sessionId': serializer.toJson<int>(sessionId),
      'habitId': serializer.toJson<String>(habitId),
      'effectiveFrom': serializer.toJson<LocalDate>(effectiveFrom),
      'target': serializer.toJson<int>(target),
      'minimumTarget': serializer.toJson<int>(minimumTarget),
      'enabled': serializer.toJson<bool>(enabled),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  HabitRevisionRow copyWith({
    int? sessionId,
    String? habitId,
    LocalDate? effectiveFrom,
    int? target,
    int? minimumTarget,
    bool? enabled,
    DateTime? createdAt,
  }) => HabitRevisionRow(
    sessionId: sessionId ?? this.sessionId,
    habitId: habitId ?? this.habitId,
    effectiveFrom: effectiveFrom ?? this.effectiveFrom,
    target: target ?? this.target,
    minimumTarget: minimumTarget ?? this.minimumTarget,
    enabled: enabled ?? this.enabled,
    createdAt: createdAt ?? this.createdAt,
  );
  HabitRevisionRow copyWithCompanion(HabitRevisionsCompanion data) {
    return HabitRevisionRow(
      sessionId: data.sessionId.present ? data.sessionId.value : this.sessionId,
      habitId: data.habitId.present ? data.habitId.value : this.habitId,
      effectiveFrom: data.effectiveFrom.present
          ? data.effectiveFrom.value
          : this.effectiveFrom,
      target: data.target.present ? data.target.value : this.target,
      minimumTarget: data.minimumTarget.present
          ? data.minimumTarget.value
          : this.minimumTarget,
      enabled: data.enabled.present ? data.enabled.value : this.enabled,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('HabitRevisionRow(')
          ..write('sessionId: $sessionId, ')
          ..write('habitId: $habitId, ')
          ..write('effectiveFrom: $effectiveFrom, ')
          ..write('target: $target, ')
          ..write('minimumTarget: $minimumTarget, ')
          ..write('enabled: $enabled, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    sessionId,
    habitId,
    effectiveFrom,
    target,
    minimumTarget,
    enabled,
    createdAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is HabitRevisionRow &&
          other.sessionId == this.sessionId &&
          other.habitId == this.habitId &&
          other.effectiveFrom == this.effectiveFrom &&
          other.target == this.target &&
          other.minimumTarget == this.minimumTarget &&
          other.enabled == this.enabled &&
          other.createdAt == this.createdAt);
}

class HabitRevisionsCompanion extends UpdateCompanion<HabitRevisionRow> {
  final Value<int> sessionId;
  final Value<String> habitId;
  final Value<LocalDate> effectiveFrom;
  final Value<int> target;
  final Value<int> minimumTarget;
  final Value<bool> enabled;
  final Value<DateTime> createdAt;
  final Value<int> rowid;
  const HabitRevisionsCompanion({
    this.sessionId = const Value.absent(),
    this.habitId = const Value.absent(),
    this.effectiveFrom = const Value.absent(),
    this.target = const Value.absent(),
    this.minimumTarget = const Value.absent(),
    this.enabled = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  HabitRevisionsCompanion.insert({
    required int sessionId,
    required String habitId,
    required LocalDate effectiveFrom,
    required int target,
    required int minimumTarget,
    required bool enabled,
    required DateTime createdAt,
    this.rowid = const Value.absent(),
  }) : sessionId = Value(sessionId),
       habitId = Value(habitId),
       effectiveFrom = Value(effectiveFrom),
       target = Value(target),
       minimumTarget = Value(minimumTarget),
       enabled = Value(enabled),
       createdAt = Value(createdAt);
  static Insertable<HabitRevisionRow> custom({
    Expression<int>? sessionId,
    Expression<String>? habitId,
    Expression<String>? effectiveFrom,
    Expression<int>? target,
    Expression<int>? minimumTarget,
    Expression<bool>? enabled,
    Expression<DateTime>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (sessionId != null) 'session_id': sessionId,
      if (habitId != null) 'habit_id': habitId,
      if (effectiveFrom != null) 'effective_from': effectiveFrom,
      if (target != null) 'target': target,
      if (minimumTarget != null) 'minimum_target': minimumTarget,
      if (enabled != null) 'enabled': enabled,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  HabitRevisionsCompanion copyWith({
    Value<int>? sessionId,
    Value<String>? habitId,
    Value<LocalDate>? effectiveFrom,
    Value<int>? target,
    Value<int>? minimumTarget,
    Value<bool>? enabled,
    Value<DateTime>? createdAt,
    Value<int>? rowid,
  }) {
    return HabitRevisionsCompanion(
      sessionId: sessionId ?? this.sessionId,
      habitId: habitId ?? this.habitId,
      effectiveFrom: effectiveFrom ?? this.effectiveFrom,
      target: target ?? this.target,
      minimumTarget: minimumTarget ?? this.minimumTarget,
      enabled: enabled ?? this.enabled,
      createdAt: createdAt ?? this.createdAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (sessionId.present) {
      map['session_id'] = Variable<int>(sessionId.value);
    }
    if (habitId.present) {
      map['habit_id'] = Variable<String>(habitId.value);
    }
    if (effectiveFrom.present) {
      map['effective_from'] = Variable<String>(
        $HabitRevisionsTable.$convertereffectiveFrom.toSql(effectiveFrom.value),
      );
    }
    if (target.present) {
      map['target'] = Variable<int>(target.value);
    }
    if (minimumTarget.present) {
      map['minimum_target'] = Variable<int>(minimumTarget.value);
    }
    if (enabled.present) {
      map['enabled'] = Variable<bool>(enabled.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('HabitRevisionsCompanion(')
          ..write('sessionId: $sessionId, ')
          ..write('habitId: $habitId, ')
          ..write('effectiveFrom: $effectiveFrom, ')
          ..write('target: $target, ')
          ..write('minimumTarget: $minimumTarget, ')
          ..write('enabled: $enabled, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $DayModesTable extends DayModes
    with TableInfo<$DayModesTable, DayModeRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $DayModesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _sessionIdMeta = const VerificationMeta(
    'sessionId',
  );
  @override
  late final GeneratedColumn<int> sessionId = GeneratedColumn<int>(
    'session_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES winter_arc_sessions (id) ON DELETE CASCADE',
    ),
  );
  @override
  late final GeneratedColumnWithTypeConverter<LocalDate, String> date =
      GeneratedColumn<String>(
        'date',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<LocalDate>($DayModesTable.$converterdate);
  @override
  late final GeneratedColumnWithTypeConverter<DayMode, String> mode =
      GeneratedColumn<String>(
        'mode',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<DayMode>($DayModesTable.$convertermode);
  static const VerificationMeta _changedAtMeta = const VerificationMeta(
    'changedAt',
  );
  @override
  late final GeneratedColumn<DateTime> changedAt = GeneratedColumn<DateTime>(
    'changed_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [sessionId, date, mode, changedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'day_modes';
  @override
  VerificationContext validateIntegrity(
    Insertable<DayModeRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('session_id')) {
      context.handle(
        _sessionIdMeta,
        sessionId.isAcceptableOrUnknown(data['session_id']!, _sessionIdMeta),
      );
    } else if (isInserting) {
      context.missing(_sessionIdMeta);
    }
    if (data.containsKey('changed_at')) {
      context.handle(
        _changedAtMeta,
        changedAt.isAcceptableOrUnknown(data['changed_at']!, _changedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_changedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {sessionId, date};
  @override
  DayModeRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return DayModeRow(
      sessionId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}session_id'],
      )!,
      date: $DayModesTable.$converterdate.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}date'],
        )!,
      ),
      mode: $DayModesTable.$convertermode.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}mode'],
        )!,
      ),
      changedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}changed_at'],
      )!,
    );
  }

  @override
  $DayModesTable createAlias(String alias) {
    return $DayModesTable(attachedDatabase, alias);
  }

  static TypeConverter<LocalDate, String> $converterdate =
      const LocalDateConverter();
  static JsonTypeConverter2<DayMode, String, String> $convertermode =
      const EnumNameConverter<DayMode>(DayMode.values);
}

class DayModeRow extends DataClass implements Insertable<DayModeRow> {
  final int sessionId;
  final LocalDate date;
  final DayMode mode;
  final DateTime changedAt;
  const DayModeRow({
    required this.sessionId,
    required this.date,
    required this.mode,
    required this.changedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['session_id'] = Variable<int>(sessionId);
    {
      map['date'] = Variable<String>($DayModesTable.$converterdate.toSql(date));
    }
    {
      map['mode'] = Variable<String>($DayModesTable.$convertermode.toSql(mode));
    }
    map['changed_at'] = Variable<DateTime>(changedAt);
    return map;
  }

  DayModesCompanion toCompanion(bool nullToAbsent) {
    return DayModesCompanion(
      sessionId: Value(sessionId),
      date: Value(date),
      mode: Value(mode),
      changedAt: Value(changedAt),
    );
  }

  factory DayModeRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return DayModeRow(
      sessionId: serializer.fromJson<int>(json['sessionId']),
      date: serializer.fromJson<LocalDate>(json['date']),
      mode: $DayModesTable.$convertermode.fromJson(
        serializer.fromJson<String>(json['mode']),
      ),
      changedAt: serializer.fromJson<DateTime>(json['changedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'sessionId': serializer.toJson<int>(sessionId),
      'date': serializer.toJson<LocalDate>(date),
      'mode': serializer.toJson<String>(
        $DayModesTable.$convertermode.toJson(mode),
      ),
      'changedAt': serializer.toJson<DateTime>(changedAt),
    };
  }

  DayModeRow copyWith({
    int? sessionId,
    LocalDate? date,
    DayMode? mode,
    DateTime? changedAt,
  }) => DayModeRow(
    sessionId: sessionId ?? this.sessionId,
    date: date ?? this.date,
    mode: mode ?? this.mode,
    changedAt: changedAt ?? this.changedAt,
  );
  DayModeRow copyWithCompanion(DayModesCompanion data) {
    return DayModeRow(
      sessionId: data.sessionId.present ? data.sessionId.value : this.sessionId,
      date: data.date.present ? data.date.value : this.date,
      mode: data.mode.present ? data.mode.value : this.mode,
      changedAt: data.changedAt.present ? data.changedAt.value : this.changedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('DayModeRow(')
          ..write('sessionId: $sessionId, ')
          ..write('date: $date, ')
          ..write('mode: $mode, ')
          ..write('changedAt: $changedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(sessionId, date, mode, changedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DayModeRow &&
          other.sessionId == this.sessionId &&
          other.date == this.date &&
          other.mode == this.mode &&
          other.changedAt == this.changedAt);
}

class DayModesCompanion extends UpdateCompanion<DayModeRow> {
  final Value<int> sessionId;
  final Value<LocalDate> date;
  final Value<DayMode> mode;
  final Value<DateTime> changedAt;
  final Value<int> rowid;
  const DayModesCompanion({
    this.sessionId = const Value.absent(),
    this.date = const Value.absent(),
    this.mode = const Value.absent(),
    this.changedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  DayModesCompanion.insert({
    required int sessionId,
    required LocalDate date,
    required DayMode mode,
    required DateTime changedAt,
    this.rowid = const Value.absent(),
  }) : sessionId = Value(sessionId),
       date = Value(date),
       mode = Value(mode),
       changedAt = Value(changedAt);
  static Insertable<DayModeRow> custom({
    Expression<int>? sessionId,
    Expression<String>? date,
    Expression<String>? mode,
    Expression<DateTime>? changedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (sessionId != null) 'session_id': sessionId,
      if (date != null) 'date': date,
      if (mode != null) 'mode': mode,
      if (changedAt != null) 'changed_at': changedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  DayModesCompanion copyWith({
    Value<int>? sessionId,
    Value<LocalDate>? date,
    Value<DayMode>? mode,
    Value<DateTime>? changedAt,
    Value<int>? rowid,
  }) {
    return DayModesCompanion(
      sessionId: sessionId ?? this.sessionId,
      date: date ?? this.date,
      mode: mode ?? this.mode,
      changedAt: changedAt ?? this.changedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (sessionId.present) {
      map['session_id'] = Variable<int>(sessionId.value);
    }
    if (date.present) {
      map['date'] = Variable<String>(
        $DayModesTable.$converterdate.toSql(date.value),
      );
    }
    if (mode.present) {
      map['mode'] = Variable<String>(
        $DayModesTable.$convertermode.toSql(mode.value),
      );
    }
    if (changedAt.present) {
      map['changed_at'] = Variable<DateTime>(changedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('DayModesCompanion(')
          ..write('sessionId: $sessionId, ')
          ..write('date: $date, ')
          ..write('mode: $mode, ')
          ..write('changedAt: $changedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $AchievementUnlocksTable extends AchievementUnlocks
    with TableInfo<$AchievementUnlocksTable, AchievementUnlockRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AchievementUnlocksTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _sessionIdMeta = const VerificationMeta(
    'sessionId',
  );
  @override
  late final GeneratedColumn<int> sessionId = GeneratedColumn<int>(
    'session_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES winter_arc_sessions (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _achievementKeyMeta = const VerificationMeta(
    'achievementKey',
  );
  @override
  late final GeneratedColumn<String> achievementKey = GeneratedColumn<String>(
    'achievement_key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumnWithTypeConverter<LocalDate, String> unlockedOn =
      GeneratedColumn<String>(
        'unlocked_on',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<LocalDate>($AchievementUnlocksTable.$converterunlockedOn);
  static const VerificationMeta _unlockedAtMeta = const VerificationMeta(
    'unlockedAt',
  );
  @override
  late final GeneratedColumn<DateTime> unlockedAt = GeneratedColumn<DateTime>(
    'unlocked_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    sessionId,
    achievementKey,
    unlockedOn,
    unlockedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'achievement_unlocks';
  @override
  VerificationContext validateIntegrity(
    Insertable<AchievementUnlockRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('session_id')) {
      context.handle(
        _sessionIdMeta,
        sessionId.isAcceptableOrUnknown(data['session_id']!, _sessionIdMeta),
      );
    } else if (isInserting) {
      context.missing(_sessionIdMeta);
    }
    if (data.containsKey('achievement_key')) {
      context.handle(
        _achievementKeyMeta,
        achievementKey.isAcceptableOrUnknown(
          data['achievement_key']!,
          _achievementKeyMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_achievementKeyMeta);
    }
    if (data.containsKey('unlocked_at')) {
      context.handle(
        _unlockedAtMeta,
        unlockedAt.isAcceptableOrUnknown(data['unlocked_at']!, _unlockedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_unlockedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {sessionId, achievementKey};
  @override
  AchievementUnlockRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return AchievementUnlockRow(
      sessionId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}session_id'],
      )!,
      achievementKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}achievement_key'],
      )!,
      unlockedOn: $AchievementUnlocksTable.$converterunlockedOn.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}unlocked_on'],
        )!,
      ),
      unlockedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}unlocked_at'],
      )!,
    );
  }

  @override
  $AchievementUnlocksTable createAlias(String alias) {
    return $AchievementUnlocksTable(attachedDatabase, alias);
  }

  static TypeConverter<LocalDate, String> $converterunlockedOn =
      const LocalDateConverter();
}

class AchievementUnlockRow extends DataClass
    implements Insertable<AchievementUnlockRow> {
  final int sessionId;

  /// Stable `AchievementKey.id`, e.g. `first_rep`.
  final String achievementKey;

  /// The challenge date on which it was earned.
  final LocalDate unlockedOn;

  /// When the unlock was first persisted.
  final DateTime unlockedAt;
  const AchievementUnlockRow({
    required this.sessionId,
    required this.achievementKey,
    required this.unlockedOn,
    required this.unlockedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['session_id'] = Variable<int>(sessionId);
    map['achievement_key'] = Variable<String>(achievementKey);
    {
      map['unlocked_on'] = Variable<String>(
        $AchievementUnlocksTable.$converterunlockedOn.toSql(unlockedOn),
      );
    }
    map['unlocked_at'] = Variable<DateTime>(unlockedAt);
    return map;
  }

  AchievementUnlocksCompanion toCompanion(bool nullToAbsent) {
    return AchievementUnlocksCompanion(
      sessionId: Value(sessionId),
      achievementKey: Value(achievementKey),
      unlockedOn: Value(unlockedOn),
      unlockedAt: Value(unlockedAt),
    );
  }

  factory AchievementUnlockRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return AchievementUnlockRow(
      sessionId: serializer.fromJson<int>(json['sessionId']),
      achievementKey: serializer.fromJson<String>(json['achievementKey']),
      unlockedOn: serializer.fromJson<LocalDate>(json['unlockedOn']),
      unlockedAt: serializer.fromJson<DateTime>(json['unlockedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'sessionId': serializer.toJson<int>(sessionId),
      'achievementKey': serializer.toJson<String>(achievementKey),
      'unlockedOn': serializer.toJson<LocalDate>(unlockedOn),
      'unlockedAt': serializer.toJson<DateTime>(unlockedAt),
    };
  }

  AchievementUnlockRow copyWith({
    int? sessionId,
    String? achievementKey,
    LocalDate? unlockedOn,
    DateTime? unlockedAt,
  }) => AchievementUnlockRow(
    sessionId: sessionId ?? this.sessionId,
    achievementKey: achievementKey ?? this.achievementKey,
    unlockedOn: unlockedOn ?? this.unlockedOn,
    unlockedAt: unlockedAt ?? this.unlockedAt,
  );
  AchievementUnlockRow copyWithCompanion(AchievementUnlocksCompanion data) {
    return AchievementUnlockRow(
      sessionId: data.sessionId.present ? data.sessionId.value : this.sessionId,
      achievementKey: data.achievementKey.present
          ? data.achievementKey.value
          : this.achievementKey,
      unlockedOn: data.unlockedOn.present
          ? data.unlockedOn.value
          : this.unlockedOn,
      unlockedAt: data.unlockedAt.present
          ? data.unlockedAt.value
          : this.unlockedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('AchievementUnlockRow(')
          ..write('sessionId: $sessionId, ')
          ..write('achievementKey: $achievementKey, ')
          ..write('unlockedOn: $unlockedOn, ')
          ..write('unlockedAt: $unlockedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(sessionId, achievementKey, unlockedOn, unlockedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AchievementUnlockRow &&
          other.sessionId == this.sessionId &&
          other.achievementKey == this.achievementKey &&
          other.unlockedOn == this.unlockedOn &&
          other.unlockedAt == this.unlockedAt);
}

class AchievementUnlocksCompanion
    extends UpdateCompanion<AchievementUnlockRow> {
  final Value<int> sessionId;
  final Value<String> achievementKey;
  final Value<LocalDate> unlockedOn;
  final Value<DateTime> unlockedAt;
  final Value<int> rowid;
  const AchievementUnlocksCompanion({
    this.sessionId = const Value.absent(),
    this.achievementKey = const Value.absent(),
    this.unlockedOn = const Value.absent(),
    this.unlockedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  AchievementUnlocksCompanion.insert({
    required int sessionId,
    required String achievementKey,
    required LocalDate unlockedOn,
    required DateTime unlockedAt,
    this.rowid = const Value.absent(),
  }) : sessionId = Value(sessionId),
       achievementKey = Value(achievementKey),
       unlockedOn = Value(unlockedOn),
       unlockedAt = Value(unlockedAt);
  static Insertable<AchievementUnlockRow> custom({
    Expression<int>? sessionId,
    Expression<String>? achievementKey,
    Expression<String>? unlockedOn,
    Expression<DateTime>? unlockedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (sessionId != null) 'session_id': sessionId,
      if (achievementKey != null) 'achievement_key': achievementKey,
      if (unlockedOn != null) 'unlocked_on': unlockedOn,
      if (unlockedAt != null) 'unlocked_at': unlockedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  AchievementUnlocksCompanion copyWith({
    Value<int>? sessionId,
    Value<String>? achievementKey,
    Value<LocalDate>? unlockedOn,
    Value<DateTime>? unlockedAt,
    Value<int>? rowid,
  }) {
    return AchievementUnlocksCompanion(
      sessionId: sessionId ?? this.sessionId,
      achievementKey: achievementKey ?? this.achievementKey,
      unlockedOn: unlockedOn ?? this.unlockedOn,
      unlockedAt: unlockedAt ?? this.unlockedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (sessionId.present) {
      map['session_id'] = Variable<int>(sessionId.value);
    }
    if (achievementKey.present) {
      map['achievement_key'] = Variable<String>(achievementKey.value);
    }
    if (unlockedOn.present) {
      map['unlocked_on'] = Variable<String>(
        $AchievementUnlocksTable.$converterunlockedOn.toSql(unlockedOn.value),
      );
    }
    if (unlockedAt.present) {
      map['unlocked_at'] = Variable<DateTime>(unlockedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('AchievementUnlocksCompanion(')
          ..write('sessionId: $sessionId, ')
          ..write('achievementKey: $achievementKey, ')
          ..write('unlockedOn: $unlockedOn, ')
          ..write('unlockedAt: $unlockedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $WinterArcSessionsTable winterArcSessions =
      $WinterArcSessionsTable(this);
  late final $HabitsTable habits = $HabitsTable(this);
  late final $DailyHabitProgressEntriesTable dailyHabitProgressEntries =
      $DailyHabitProgressEntriesTable(this);
  late final $XpTransactionsTable xpTransactions = $XpTransactionsTable(this);
  late final $HabitRevisionsTable habitRevisions = $HabitRevisionsTable(this);
  late final $DayModesTable dayModes = $DayModesTable(this);
  late final $AchievementUnlocksTable achievementUnlocks =
      $AchievementUnlocksTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    winterArcSessions,
    habits,
    dailyHabitProgressEntries,
    xpTransactions,
    habitRevisions,
    dayModes,
    achievementUnlocks,
  ];
  @override
  StreamQueryUpdateRules get streamUpdateRules => const StreamQueryUpdateRules([
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'winter_arc_sessions',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('habits', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'winter_arc_sessions',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('xp_transactions', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'winter_arc_sessions',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('day_modes', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'winter_arc_sessions',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('achievement_unlocks', kind: UpdateKind.delete)],
    ),
  ]);
}

typedef $$WinterArcSessionsTableCreateCompanionBuilder =
    WinterArcSessionsCompanion Function({
      Value<int> id,
      required LocalDate startDate,
      required LocalDate endDate,
      required WinterArcStatus status,
      required DateTime createdAt,
      Value<DateTime?> startedAt,
    });
typedef $$WinterArcSessionsTableUpdateCompanionBuilder =
    WinterArcSessionsCompanion Function({
      Value<int> id,
      Value<LocalDate> startDate,
      Value<LocalDate> endDate,
      Value<WinterArcStatus> status,
      Value<DateTime> createdAt,
      Value<DateTime?> startedAt,
    });

final class $$WinterArcSessionsTableReferences
    extends BaseReferences<_$AppDatabase, $WinterArcSessionsTable, SessionRow> {
  $$WinterArcSessionsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static MultiTypedResultKey<$HabitsTable, List<HabitRow>> _habitsRefsTable(
    _$AppDatabase db,
  ) => MultiTypedResultKey.fromTable(
    db.habits,
    aliasName: 'winter_arc_sessions__id__habits__session_id',
  );

  $$HabitsTableProcessedTableManager get habitsRefs {
    final manager = $$HabitsTableTableManager(
      $_db,
      $_db.habits,
    ).filter((f) => f.sessionId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(_habitsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$XpTransactionsTable, List<XpTransactionRow>>
  _xpTransactionsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.xpTransactions,
    aliasName: 'winter_arc_sessions__id__xp_transactions__session_id',
  );

  $$XpTransactionsTableProcessedTableManager get xpTransactionsRefs {
    final manager = $$XpTransactionsTableTableManager(
      $_db,
      $_db.xpTransactions,
    ).filter((f) => f.sessionId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(_xpTransactionsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$DayModesTable, List<DayModeRow>>
  _dayModesRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.dayModes,
    aliasName: 'winter_arc_sessions__id__day_modes__session_id',
  );

  $$DayModesTableProcessedTableManager get dayModesRefs {
    final manager = $$DayModesTableTableManager(
      $_db,
      $_db.dayModes,
    ).filter((f) => f.sessionId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(_dayModesRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<
    $AchievementUnlocksTable,
    List<AchievementUnlockRow>
  >
  _achievementUnlocksRefsTable(_$AppDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.achievementUnlocks,
        aliasName: 'winter_arc_sessions__id__achievement_unlocks__session_id',
      );

  $$AchievementUnlocksTableProcessedTableManager get achievementUnlocksRefs {
    final manager = $$AchievementUnlocksTableTableManager(
      $_db,
      $_db.achievementUnlocks,
    ).filter((f) => f.sessionId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _achievementUnlocksRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$WinterArcSessionsTableFilterComposer
    extends Composer<_$AppDatabase, $WinterArcSessionsTable> {
  $$WinterArcSessionsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<LocalDate, LocalDate, String> get startDate =>
      $composableBuilder(
        column: $table.startDate,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnWithTypeConverterFilters<LocalDate, LocalDate, String> get endDate =>
      $composableBuilder(
        column: $table.endDate,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnWithTypeConverterFilters<WinterArcStatus, WinterArcStatus, String>
  get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get startedAt => $composableBuilder(
    column: $table.startedAt,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> habitsRefs(
    Expression<bool> Function($$HabitsTableFilterComposer f) f,
  ) {
    final $$HabitsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.habits,
      getReferencedColumn: (t) => t.sessionId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$HabitsTableFilterComposer(
            $db: $db,
            $table: $db.habits,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> xpTransactionsRefs(
    Expression<bool> Function($$XpTransactionsTableFilterComposer f) f,
  ) {
    final $$XpTransactionsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.xpTransactions,
      getReferencedColumn: (t) => t.sessionId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$XpTransactionsTableFilterComposer(
            $db: $db,
            $table: $db.xpTransactions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> dayModesRefs(
    Expression<bool> Function($$DayModesTableFilterComposer f) f,
  ) {
    final $$DayModesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.dayModes,
      getReferencedColumn: (t) => t.sessionId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$DayModesTableFilterComposer(
            $db: $db,
            $table: $db.dayModes,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> achievementUnlocksRefs(
    Expression<bool> Function($$AchievementUnlocksTableFilterComposer f) f,
  ) {
    final $$AchievementUnlocksTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.achievementUnlocks,
      getReferencedColumn: (t) => t.sessionId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$AchievementUnlocksTableFilterComposer(
            $db: $db,
            $table: $db.achievementUnlocks,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$WinterArcSessionsTableOrderingComposer
    extends Composer<_$AppDatabase, $WinterArcSessionsTable> {
  $$WinterArcSessionsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get startDate => $composableBuilder(
    column: $table.startDate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get endDate => $composableBuilder(
    column: $table.endDate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get startedAt => $composableBuilder(
    column: $table.startedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$WinterArcSessionsTableAnnotationComposer
    extends Composer<_$AppDatabase, $WinterArcSessionsTable> {
  $$WinterArcSessionsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumnWithTypeConverter<LocalDate, String> get startDate =>
      $composableBuilder(column: $table.startDate, builder: (column) => column);

  GeneratedColumnWithTypeConverter<LocalDate, String> get endDate =>
      $composableBuilder(column: $table.endDate, builder: (column) => column);

  GeneratedColumnWithTypeConverter<WinterArcStatus, String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get startedAt =>
      $composableBuilder(column: $table.startedAt, builder: (column) => column);

  Expression<T> habitsRefs<T extends Object>(
    Expression<T> Function($$HabitsTableAnnotationComposer a) f,
  ) {
    final $$HabitsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.habits,
      getReferencedColumn: (t) => t.sessionId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$HabitsTableAnnotationComposer(
            $db: $db,
            $table: $db.habits,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> xpTransactionsRefs<T extends Object>(
    Expression<T> Function($$XpTransactionsTableAnnotationComposer a) f,
  ) {
    final $$XpTransactionsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.xpTransactions,
      getReferencedColumn: (t) => t.sessionId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$XpTransactionsTableAnnotationComposer(
            $db: $db,
            $table: $db.xpTransactions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> dayModesRefs<T extends Object>(
    Expression<T> Function($$DayModesTableAnnotationComposer a) f,
  ) {
    final $$DayModesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.dayModes,
      getReferencedColumn: (t) => t.sessionId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$DayModesTableAnnotationComposer(
            $db: $db,
            $table: $db.dayModes,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> achievementUnlocksRefs<T extends Object>(
    Expression<T> Function($$AchievementUnlocksTableAnnotationComposer a) f,
  ) {
    final $$AchievementUnlocksTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.id,
          referencedTable: $db.achievementUnlocks,
          getReferencedColumn: (t) => t.sessionId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$AchievementUnlocksTableAnnotationComposer(
                $db: $db,
                $table: $db.achievementUnlocks,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }
}

class $$WinterArcSessionsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $WinterArcSessionsTable,
          SessionRow,
          $$WinterArcSessionsTableFilterComposer,
          $$WinterArcSessionsTableOrderingComposer,
          $$WinterArcSessionsTableAnnotationComposer,
          $$WinterArcSessionsTableCreateCompanionBuilder,
          $$WinterArcSessionsTableUpdateCompanionBuilder,
          (SessionRow, $$WinterArcSessionsTableReferences),
          SessionRow,
          PrefetchHooks Function({
            bool habitsRefs,
            bool xpTransactionsRefs,
            bool dayModesRefs,
            bool achievementUnlocksRefs,
          })
        > {
  $$WinterArcSessionsTableTableManager(
    _$AppDatabase db,
    $WinterArcSessionsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$WinterArcSessionsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$WinterArcSessionsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$WinterArcSessionsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<LocalDate> startDate = const Value.absent(),
                Value<LocalDate> endDate = const Value.absent(),
                Value<WinterArcStatus> status = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime?> startedAt = const Value.absent(),
              }) => WinterArcSessionsCompanion(
                id: id,
                startDate: startDate,
                endDate: endDate,
                status: status,
                createdAt: createdAt,
                startedAt: startedAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required LocalDate startDate,
                required LocalDate endDate,
                required WinterArcStatus status,
                required DateTime createdAt,
                Value<DateTime?> startedAt = const Value.absent(),
              }) => WinterArcSessionsCompanion.insert(
                id: id,
                startDate: startDate,
                endDate: endDate,
                status: status,
                createdAt: createdAt,
                startedAt: startedAt,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$WinterArcSessionsTable, SessionRow>(table),
                  $$WinterArcSessionsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({
                habitsRefs = false,
                xpTransactionsRefs = false,
                dayModesRefs = false,
                achievementUnlocksRefs = false,
              }) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (habitsRefs) db.habits,
                    if (xpTransactionsRefs) db.xpTransactions,
                    if (dayModesRefs) db.dayModes,
                    if (achievementUnlocksRefs) db.achievementUnlocks,
                  ],
                  addJoins: null,
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (habitsRefs)
                        await $_getPrefetchedData<
                          SessionRow,
                          $WinterArcSessionsTable,
                          HabitRow
                        >(
                          currentTable: table,
                          referencedTable: $$WinterArcSessionsTableReferences
                              ._habitsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$WinterArcSessionsTableReferences(
                                db,
                                table,
                                p0,
                              ).habitsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.sessionId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (xpTransactionsRefs)
                        await $_getPrefetchedData<
                          SessionRow,
                          $WinterArcSessionsTable,
                          XpTransactionRow
                        >(
                          currentTable: table,
                          referencedTable: $$WinterArcSessionsTableReferences
                              ._xpTransactionsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$WinterArcSessionsTableReferences(
                                db,
                                table,
                                p0,
                              ).xpTransactionsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.sessionId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (dayModesRefs)
                        await $_getPrefetchedData<
                          SessionRow,
                          $WinterArcSessionsTable,
                          DayModeRow
                        >(
                          currentTable: table,
                          referencedTable: $$WinterArcSessionsTableReferences
                              ._dayModesRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$WinterArcSessionsTableReferences(
                                db,
                                table,
                                p0,
                              ).dayModesRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.sessionId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (achievementUnlocksRefs)
                        await $_getPrefetchedData<
                          SessionRow,
                          $WinterArcSessionsTable,
                          AchievementUnlockRow
                        >(
                          currentTable: table,
                          referencedTable: $$WinterArcSessionsTableReferences
                              ._achievementUnlocksRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$WinterArcSessionsTableReferences(
                                db,
                                table,
                                p0,
                              ).achievementUnlocksRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.sessionId == item.id,
                              ),
                          typedResults: items,
                        ),
                    ];
                  },
                );
              },
        ),
      );
}

typedef $$WinterArcSessionsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $WinterArcSessionsTable,
      SessionRow,
      $$WinterArcSessionsTableFilterComposer,
      $$WinterArcSessionsTableOrderingComposer,
      $$WinterArcSessionsTableAnnotationComposer,
      $$WinterArcSessionsTableCreateCompanionBuilder,
      $$WinterArcSessionsTableUpdateCompanionBuilder,
      (SessionRow, $$WinterArcSessionsTableReferences),
      SessionRow,
      PrefetchHooks Function({
        bool habitsRefs,
        bool xpTransactionsRefs,
        bool dayModesRefs,
        bool achievementUnlocksRefs,
      })
    >;
typedef $$HabitsTableCreateCompanionBuilder = HabitsCompanion Function({
  required int sessionId,
  required String id,
  required String title,
  required HabitType type,
  required int target,
  Value<String?> unit,
  required String iconKey,
  required bool enabled,
  required int sortOrder,
  required DateTime createdAt,
  Value<int> minimumTarget,
  Value<int> rowid,
});
typedef $$HabitsTableUpdateCompanionBuilder = HabitsCompanion Function({
  Value<int> sessionId,
  Value<String> id,
  Value<String> title,
  Value<HabitType> type,
  Value<int> target,
  Value<String?> unit,
  Value<String> iconKey,
  Value<bool> enabled,
  Value<int> sortOrder,
  Value<DateTime> createdAt,
  Value<int> minimumTarget,
  Value<int> rowid,
});

final class $$HabitsTableReferences
    extends BaseReferences<_$AppDatabase, $HabitsTable, HabitRow> {
  $$HabitsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $WinterArcSessionsTable _sessionIdTable(_$AppDatabase db) => db
      .winterArcSessions
      .createAlias('habits__session_id__winter_arc_sessions__id');

  $$WinterArcSessionsTableProcessedTableManager get sessionId {
    final $_column = $_itemColumn<int>('session_id')!;

    final manager = $$WinterArcSessionsTableTableManager(
      $_db,
      $_db.winterArcSessions,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_sessionIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$HabitsTableFilterComposer
    extends Composer<_$AppDatabase, $HabitsTable> {
  $$HabitsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<HabitType, HabitType, String> get type =>
      $composableBuilder(
        column: $table.type,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnFilters<int> get target => $composableBuilder(
    column: $table.target,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get unit => $composableBuilder(
    column: $table.unit,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get iconKey => $composableBuilder(
    column: $table.iconKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get enabled => $composableBuilder(
    column: $table.enabled,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sortOrder => $composableBuilder(
    column: $table.sortOrder,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get minimumTarget => $composableBuilder(
    column: $table.minimumTarget,
    builder: (column) => ColumnFilters(column),
  );

  $$WinterArcSessionsTableFilterComposer get sessionId {
    final $$WinterArcSessionsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.sessionId,
      referencedTable: $db.winterArcSessions,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$WinterArcSessionsTableFilterComposer(
            $db: $db,
            $table: $db.winterArcSessions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$HabitsTableOrderingComposer
    extends Composer<_$AppDatabase, $HabitsTable> {
  $$HabitsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get target => $composableBuilder(
    column: $table.target,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get unit => $composableBuilder(
    column: $table.unit,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get iconKey => $composableBuilder(
    column: $table.iconKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get enabled => $composableBuilder(
    column: $table.enabled,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sortOrder => $composableBuilder(
    column: $table.sortOrder,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get minimumTarget => $composableBuilder(
    column: $table.minimumTarget,
    builder: (column) => ColumnOrderings(column),
  );

  $$WinterArcSessionsTableOrderingComposer get sessionId {
    final $$WinterArcSessionsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.sessionId,
      referencedTable: $db.winterArcSessions,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$WinterArcSessionsTableOrderingComposer(
            $db: $db,
            $table: $db.winterArcSessions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$HabitsTableAnnotationComposer
    extends Composer<_$AppDatabase, $HabitsTable> {
  $$HabitsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumnWithTypeConverter<HabitType, String> get type =>
      $composableBuilder(column: $table.type, builder: (column) => column);

  GeneratedColumn<int> get target =>
      $composableBuilder(column: $table.target, builder: (column) => column);

  GeneratedColumn<String> get unit =>
      $composableBuilder(column: $table.unit, builder: (column) => column);

  GeneratedColumn<String> get iconKey =>
      $composableBuilder(column: $table.iconKey, builder: (column) => column);

  GeneratedColumn<bool> get enabled =>
      $composableBuilder(column: $table.enabled, builder: (column) => column);

  GeneratedColumn<int> get sortOrder =>
      $composableBuilder(column: $table.sortOrder, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<int> get minimumTarget => $composableBuilder(
    column: $table.minimumTarget,
    builder: (column) => column,
  );

  $$WinterArcSessionsTableAnnotationComposer get sessionId {
    final $$WinterArcSessionsTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.sessionId,
          referencedTable: $db.winterArcSessions,
          getReferencedColumn: (t) => t.id,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$WinterArcSessionsTableAnnotationComposer(
                $db: $db,
                $table: $db.winterArcSessions,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return composer;
  }
}

class $$HabitsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $HabitsTable,
          HabitRow,
          $$HabitsTableFilterComposer,
          $$HabitsTableOrderingComposer,
          $$HabitsTableAnnotationComposer,
          $$HabitsTableCreateCompanionBuilder,
          $$HabitsTableUpdateCompanionBuilder,
          (HabitRow, $$HabitsTableReferences),
          HabitRow,
          PrefetchHooks Function({bool sessionId})
        > {
  $$HabitsTableTableManager(_$AppDatabase db, $HabitsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$HabitsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$HabitsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$HabitsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> sessionId = const Value.absent(),
                Value<String> id = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<HabitType> type = const Value.absent(),
                Value<int> target = const Value.absent(),
                Value<String?> unit = const Value.absent(),
                Value<String> iconKey = const Value.absent(),
                Value<bool> enabled = const Value.absent(),
                Value<int> sortOrder = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<int> minimumTarget = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => HabitsCompanion(
                sessionId: sessionId,
                id: id,
                title: title,
                type: type,
                target: target,
                unit: unit,
                iconKey: iconKey,
                enabled: enabled,
                sortOrder: sortOrder,
                createdAt: createdAt,
                minimumTarget: minimumTarget,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required int sessionId,
                required String id,
                required String title,
                required HabitType type,
                required int target,
                Value<String?> unit = const Value.absent(),
                required String iconKey,
                required bool enabled,
                required int sortOrder,
                required DateTime createdAt,
                Value<int> minimumTarget = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => HabitsCompanion.insert(
                sessionId: sessionId,
                id: id,
                title: title,
                type: type,
                target: target,
                unit: unit,
                iconKey: iconKey,
                enabled: enabled,
                sortOrder: sortOrder,
                createdAt: createdAt,
                minimumTarget: minimumTarget,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$HabitsTable, HabitRow>(table),
                  $$HabitsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({sessionId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (sessionId) {
                      state = state.withJoin(
                        currentTable: table,
                        currentColumn: table.sessionId,
                        referencedTable: $$HabitsTableReferences
                            ._sessionIdTable(db),
                        referencedColumn: $$HabitsTableReferences
                            ._sessionIdTable(db)
                            .id,
                      ) as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$HabitsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $HabitsTable,
      HabitRow,
      $$HabitsTableFilterComposer,
      $$HabitsTableOrderingComposer,
      $$HabitsTableAnnotationComposer,
      $$HabitsTableCreateCompanionBuilder,
      $$HabitsTableUpdateCompanionBuilder,
      (HabitRow, $$HabitsTableReferences),
      HabitRow,
      PrefetchHooks Function({bool sessionId})
    >;
typedef $$DailyHabitProgressEntriesTableCreateCompanionBuilder =
    DailyHabitProgressEntriesCompanion Function({
      required int sessionId,
      required String habitId,
      required LocalDate date,
      required int currentValue,
      required bool completed,
      Value<DateTime?> completedAt,
      required DateTime updatedAt,
      Value<int> rowid,
    });
typedef $$DailyHabitProgressEntriesTableUpdateCompanionBuilder =
    DailyHabitProgressEntriesCompanion Function({
      Value<int> sessionId,
      Value<String> habitId,
      Value<LocalDate> date,
      Value<int> currentValue,
      Value<bool> completed,
      Value<DateTime?> completedAt,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

class $$DailyHabitProgressEntriesTableFilterComposer
    extends Composer<_$AppDatabase, $DailyHabitProgressEntriesTable> {
  $$DailyHabitProgressEntriesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get sessionId => $composableBuilder(
    column: $table.sessionId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get habitId => $composableBuilder(
    column: $table.habitId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<LocalDate, LocalDate, String> get date =>
      $composableBuilder(
        column: $table.date,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnFilters<int> get currentValue => $composableBuilder(
    column: $table.currentValue,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get completed => $composableBuilder(
    column: $table.completed,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get completedAt => $composableBuilder(
    column: $table.completedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$DailyHabitProgressEntriesTableOrderingComposer
    extends Composer<_$AppDatabase, $DailyHabitProgressEntriesTable> {
  $$DailyHabitProgressEntriesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get sessionId => $composableBuilder(
    column: $table.sessionId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get habitId => $composableBuilder(
    column: $table.habitId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get date => $composableBuilder(
    column: $table.date,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get currentValue => $composableBuilder(
    column: $table.currentValue,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get completed => $composableBuilder(
    column: $table.completed,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get completedAt => $composableBuilder(
    column: $table.completedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$DailyHabitProgressEntriesTableAnnotationComposer
    extends Composer<_$AppDatabase, $DailyHabitProgressEntriesTable> {
  $$DailyHabitProgressEntriesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get sessionId =>
      $composableBuilder(column: $table.sessionId, builder: (column) => column);

  GeneratedColumn<String> get habitId =>
      $composableBuilder(column: $table.habitId, builder: (column) => column);

  GeneratedColumnWithTypeConverter<LocalDate, String> get date =>
      $composableBuilder(column: $table.date, builder: (column) => column);

  GeneratedColumn<int> get currentValue => $composableBuilder(
    column: $table.currentValue,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get completed =>
      $composableBuilder(column: $table.completed, builder: (column) => column);

  GeneratedColumn<DateTime> get completedAt => $composableBuilder(
    column: $table.completedAt,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$DailyHabitProgressEntriesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $DailyHabitProgressEntriesTable,
          HabitProgressRow,
          $$DailyHabitProgressEntriesTableFilterComposer,
          $$DailyHabitProgressEntriesTableOrderingComposer,
          $$DailyHabitProgressEntriesTableAnnotationComposer,
          $$DailyHabitProgressEntriesTableCreateCompanionBuilder,
          $$DailyHabitProgressEntriesTableUpdateCompanionBuilder,
          (
            HabitProgressRow,
            BaseReferences<
              _$AppDatabase,
              $DailyHabitProgressEntriesTable,
              HabitProgressRow
            >,
          ),
          HabitProgressRow,
          PrefetchHooks Function()
        > {
  $$DailyHabitProgressEntriesTableTableManager(
    _$AppDatabase db,
    $DailyHabitProgressEntriesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$DailyHabitProgressEntriesTableFilterComposer(
                $db: db,
                $table: table,
              ),
          createOrderingComposer: () =>
              $$DailyHabitProgressEntriesTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$DailyHabitProgressEntriesTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<int> sessionId = const Value.absent(),
                Value<String> habitId = const Value.absent(),
                Value<LocalDate> date = const Value.absent(),
                Value<int> currentValue = const Value.absent(),
                Value<bool> completed = const Value.absent(),
                Value<DateTime?> completedAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => DailyHabitProgressEntriesCompanion(
                sessionId: sessionId,
                habitId: habitId,
                date: date,
                currentValue: currentValue,
                completed: completed,
                completedAt: completedAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required int sessionId,
                required String habitId,
                required LocalDate date,
                required int currentValue,
                required bool completed,
                Value<DateTime?> completedAt = const Value.absent(),
                required DateTime updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => DailyHabitProgressEntriesCompanion.insert(
                sessionId: sessionId,
                habitId: habitId,
                date: date,
                currentValue: currentValue,
                completed: completed,
                completedAt: completedAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<
                    $DailyHabitProgressEntriesTable,
                    HabitProgressRow
                  >(table),
                  BaseReferences<
                    _$AppDatabase,
                    $DailyHabitProgressEntriesTable,
                    HabitProgressRow
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$DailyHabitProgressEntriesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $DailyHabitProgressEntriesTable,
      HabitProgressRow,
      $$DailyHabitProgressEntriesTableFilterComposer,
      $$DailyHabitProgressEntriesTableOrderingComposer,
      $$DailyHabitProgressEntriesTableAnnotationComposer,
      $$DailyHabitProgressEntriesTableCreateCompanionBuilder,
      $$DailyHabitProgressEntriesTableUpdateCompanionBuilder,
      (
        HabitProgressRow,
        BaseReferences<
          _$AppDatabase,
          $DailyHabitProgressEntriesTable,
          HabitProgressRow
        >,
      ),
      HabitProgressRow,
      PrefetchHooks Function()
    >;
typedef $$XpTransactionsTableCreateCompanionBuilder =
    XpTransactionsCompanion Function({
      Value<int> id,
      required int sessionId,
      required String sourceKey,
      required XpReason reason,
      required int amount,
      Value<String?> habitId,
      required LocalDate date,
      required DateTime createdAt,
    });
typedef $$XpTransactionsTableUpdateCompanionBuilder =
    XpTransactionsCompanion Function({
      Value<int> id,
      Value<int> sessionId,
      Value<String> sourceKey,
      Value<XpReason> reason,
      Value<int> amount,
      Value<String?> habitId,
      Value<LocalDate> date,
      Value<DateTime> createdAt,
    });

final class $$XpTransactionsTableReferences
    extends
        BaseReferences<_$AppDatabase, $XpTransactionsTable, XpTransactionRow> {
  $$XpTransactionsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $WinterArcSessionsTable _sessionIdTable(_$AppDatabase db) => db
      .winterArcSessions
      .createAlias('xp_transactions__session_id__winter_arc_sessions__id');

  $$WinterArcSessionsTableProcessedTableManager get sessionId {
    final $_column = $_itemColumn<int>('session_id')!;

    final manager = $$WinterArcSessionsTableTableManager(
      $_db,
      $_db.winterArcSessions,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_sessionIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$XpTransactionsTableFilterComposer
    extends Composer<_$AppDatabase, $XpTransactionsTable> {
  $$XpTransactionsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sourceKey => $composableBuilder(
    column: $table.sourceKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<XpReason, XpReason, String> get reason =>
      $composableBuilder(
        column: $table.reason,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnFilters<int> get amount => $composableBuilder(
    column: $table.amount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get habitId => $composableBuilder(
    column: $table.habitId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<LocalDate, LocalDate, String> get date =>
      $composableBuilder(
        column: $table.date,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  $$WinterArcSessionsTableFilterComposer get sessionId {
    final $$WinterArcSessionsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.sessionId,
      referencedTable: $db.winterArcSessions,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$WinterArcSessionsTableFilterComposer(
            $db: $db,
            $table: $db.winterArcSessions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$XpTransactionsTableOrderingComposer
    extends Composer<_$AppDatabase, $XpTransactionsTable> {
  $$XpTransactionsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sourceKey => $composableBuilder(
    column: $table.sourceKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get reason => $composableBuilder(
    column: $table.reason,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get amount => $composableBuilder(
    column: $table.amount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get habitId => $composableBuilder(
    column: $table.habitId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get date => $composableBuilder(
    column: $table.date,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$WinterArcSessionsTableOrderingComposer get sessionId {
    final $$WinterArcSessionsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.sessionId,
      referencedTable: $db.winterArcSessions,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$WinterArcSessionsTableOrderingComposer(
            $db: $db,
            $table: $db.winterArcSessions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$XpTransactionsTableAnnotationComposer
    extends Composer<_$AppDatabase, $XpTransactionsTable> {
  $$XpTransactionsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get sourceKey =>
      $composableBuilder(column: $table.sourceKey, builder: (column) => column);

  GeneratedColumnWithTypeConverter<XpReason, String> get reason =>
      $composableBuilder(column: $table.reason, builder: (column) => column);

  GeneratedColumn<int> get amount =>
      $composableBuilder(column: $table.amount, builder: (column) => column);

  GeneratedColumn<String> get habitId =>
      $composableBuilder(column: $table.habitId, builder: (column) => column);

  GeneratedColumnWithTypeConverter<LocalDate, String> get date =>
      $composableBuilder(column: $table.date, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  $$WinterArcSessionsTableAnnotationComposer get sessionId {
    final $$WinterArcSessionsTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.sessionId,
          referencedTable: $db.winterArcSessions,
          getReferencedColumn: (t) => t.id,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$WinterArcSessionsTableAnnotationComposer(
                $db: $db,
                $table: $db.winterArcSessions,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return composer;
  }
}

class $$XpTransactionsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $XpTransactionsTable,
          XpTransactionRow,
          $$XpTransactionsTableFilterComposer,
          $$XpTransactionsTableOrderingComposer,
          $$XpTransactionsTableAnnotationComposer,
          $$XpTransactionsTableCreateCompanionBuilder,
          $$XpTransactionsTableUpdateCompanionBuilder,
          (XpTransactionRow, $$XpTransactionsTableReferences),
          XpTransactionRow,
          PrefetchHooks Function({bool sessionId})
        > {
  $$XpTransactionsTableTableManager(
    _$AppDatabase db,
    $XpTransactionsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$XpTransactionsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$XpTransactionsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$XpTransactionsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int> sessionId = const Value.absent(),
                Value<String> sourceKey = const Value.absent(),
                Value<XpReason> reason = const Value.absent(),
                Value<int> amount = const Value.absent(),
                Value<String?> habitId = const Value.absent(),
                Value<LocalDate> date = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
              }) => XpTransactionsCompanion(
                id: id,
                sessionId: sessionId,
                sourceKey: sourceKey,
                reason: reason,
                amount: amount,
                habitId: habitId,
                date: date,
                createdAt: createdAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required int sessionId,
                required String sourceKey,
                required XpReason reason,
                required int amount,
                Value<String?> habitId = const Value.absent(),
                required LocalDate date,
                required DateTime createdAt,
              }) => XpTransactionsCompanion.insert(
                id: id,
                sessionId: sessionId,
                sourceKey: sourceKey,
                reason: reason,
                amount: amount,
                habitId: habitId,
                date: date,
                createdAt: createdAt,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$XpTransactionsTable, XpTransactionRow>(table),
                  $$XpTransactionsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({sessionId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (sessionId) {
                      state = state.withJoin(
                        currentTable: table,
                        currentColumn: table.sessionId,
                        referencedTable: $$XpTransactionsTableReferences
                            ._sessionIdTable(db),
                        referencedColumn: $$XpTransactionsTableReferences
                            ._sessionIdTable(db)
                            .id,
                      ) as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$XpTransactionsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $XpTransactionsTable,
      XpTransactionRow,
      $$XpTransactionsTableFilterComposer,
      $$XpTransactionsTableOrderingComposer,
      $$XpTransactionsTableAnnotationComposer,
      $$XpTransactionsTableCreateCompanionBuilder,
      $$XpTransactionsTableUpdateCompanionBuilder,
      (XpTransactionRow, $$XpTransactionsTableReferences),
      XpTransactionRow,
      PrefetchHooks Function({bool sessionId})
    >;
typedef $$HabitRevisionsTableCreateCompanionBuilder =
    HabitRevisionsCompanion Function({
      required int sessionId,
      required String habitId,
      required LocalDate effectiveFrom,
      required int target,
      required int minimumTarget,
      required bool enabled,
      required DateTime createdAt,
      Value<int> rowid,
    });
typedef $$HabitRevisionsTableUpdateCompanionBuilder =
    HabitRevisionsCompanion Function({
      Value<int> sessionId,
      Value<String> habitId,
      Value<LocalDate> effectiveFrom,
      Value<int> target,
      Value<int> minimumTarget,
      Value<bool> enabled,
      Value<DateTime> createdAt,
      Value<int> rowid,
    });

class $$HabitRevisionsTableFilterComposer
    extends Composer<_$AppDatabase, $HabitRevisionsTable> {
  $$HabitRevisionsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get sessionId => $composableBuilder(
    column: $table.sessionId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get habitId => $composableBuilder(
    column: $table.habitId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<LocalDate, LocalDate, String>
  get effectiveFrom => $composableBuilder(
    column: $table.effectiveFrom,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );

  ColumnFilters<int> get target => $composableBuilder(
    column: $table.target,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get minimumTarget => $composableBuilder(
    column: $table.minimumTarget,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get enabled => $composableBuilder(
    column: $table.enabled,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$HabitRevisionsTableOrderingComposer
    extends Composer<_$AppDatabase, $HabitRevisionsTable> {
  $$HabitRevisionsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get sessionId => $composableBuilder(
    column: $table.sessionId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get habitId => $composableBuilder(
    column: $table.habitId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get effectiveFrom => $composableBuilder(
    column: $table.effectiveFrom,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get target => $composableBuilder(
    column: $table.target,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get minimumTarget => $composableBuilder(
    column: $table.minimumTarget,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get enabled => $composableBuilder(
    column: $table.enabled,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$HabitRevisionsTableAnnotationComposer
    extends Composer<_$AppDatabase, $HabitRevisionsTable> {
  $$HabitRevisionsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get sessionId =>
      $composableBuilder(column: $table.sessionId, builder: (column) => column);

  GeneratedColumn<String> get habitId =>
      $composableBuilder(column: $table.habitId, builder: (column) => column);

  GeneratedColumnWithTypeConverter<LocalDate, String> get effectiveFrom =>
      $composableBuilder(
        column: $table.effectiveFrom,
        builder: (column) => column,
      );

  GeneratedColumn<int> get target =>
      $composableBuilder(column: $table.target, builder: (column) => column);

  GeneratedColumn<int> get minimumTarget => $composableBuilder(
    column: $table.minimumTarget,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get enabled =>
      $composableBuilder(column: $table.enabled, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);
}

class $$HabitRevisionsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $HabitRevisionsTable,
          HabitRevisionRow,
          $$HabitRevisionsTableFilterComposer,
          $$HabitRevisionsTableOrderingComposer,
          $$HabitRevisionsTableAnnotationComposer,
          $$HabitRevisionsTableCreateCompanionBuilder,
          $$HabitRevisionsTableUpdateCompanionBuilder,
          (
            HabitRevisionRow,
            BaseReferences<
              _$AppDatabase,
              $HabitRevisionsTable,
              HabitRevisionRow
            >,
          ),
          HabitRevisionRow,
          PrefetchHooks Function()
        > {
  $$HabitRevisionsTableTableManager(
    _$AppDatabase db,
    $HabitRevisionsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$HabitRevisionsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$HabitRevisionsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$HabitRevisionsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> sessionId = const Value.absent(),
                Value<String> habitId = const Value.absent(),
                Value<LocalDate> effectiveFrom = const Value.absent(),
                Value<int> target = const Value.absent(),
                Value<int> minimumTarget = const Value.absent(),
                Value<bool> enabled = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => HabitRevisionsCompanion(
                sessionId: sessionId,
                habitId: habitId,
                effectiveFrom: effectiveFrom,
                target: target,
                minimumTarget: minimumTarget,
                enabled: enabled,
                createdAt: createdAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required int sessionId,
                required String habitId,
                required LocalDate effectiveFrom,
                required int target,
                required int minimumTarget,
                required bool enabled,
                required DateTime createdAt,
                Value<int> rowid = const Value.absent(),
              }) => HabitRevisionsCompanion.insert(
                sessionId: sessionId,
                habitId: habitId,
                effectiveFrom: effectiveFrom,
                target: target,
                minimumTarget: minimumTarget,
                enabled: enabled,
                createdAt: createdAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$HabitRevisionsTable, HabitRevisionRow>(table),
                  BaseReferences<
                    _$AppDatabase,
                    $HabitRevisionsTable,
                    HabitRevisionRow
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$HabitRevisionsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $HabitRevisionsTable,
      HabitRevisionRow,
      $$HabitRevisionsTableFilterComposer,
      $$HabitRevisionsTableOrderingComposer,
      $$HabitRevisionsTableAnnotationComposer,
      $$HabitRevisionsTableCreateCompanionBuilder,
      $$HabitRevisionsTableUpdateCompanionBuilder,
      (
        HabitRevisionRow,
        BaseReferences<_$AppDatabase, $HabitRevisionsTable, HabitRevisionRow>,
      ),
      HabitRevisionRow,
      PrefetchHooks Function()
    >;
typedef $$DayModesTableCreateCompanionBuilder = DayModesCompanion Function({
  required int sessionId,
  required LocalDate date,
  required DayMode mode,
  required DateTime changedAt,
  Value<int> rowid,
});
typedef $$DayModesTableUpdateCompanionBuilder = DayModesCompanion Function({
  Value<int> sessionId,
  Value<LocalDate> date,
  Value<DayMode> mode,
  Value<DateTime> changedAt,
  Value<int> rowid,
});

final class $$DayModesTableReferences
    extends BaseReferences<_$AppDatabase, $DayModesTable, DayModeRow> {
  $$DayModesTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $WinterArcSessionsTable _sessionIdTable(_$AppDatabase db) => db
      .winterArcSessions
      .createAlias('day_modes__session_id__winter_arc_sessions__id');

  $$WinterArcSessionsTableProcessedTableManager get sessionId {
    final $_column = $_itemColumn<int>('session_id')!;

    final manager = $$WinterArcSessionsTableTableManager(
      $_db,
      $_db.winterArcSessions,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_sessionIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$DayModesTableFilterComposer
    extends Composer<_$AppDatabase, $DayModesTable> {
  $$DayModesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnWithTypeConverterFilters<LocalDate, LocalDate, String> get date =>
      $composableBuilder(
        column: $table.date,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnWithTypeConverterFilters<DayMode, DayMode, String> get mode =>
      $composableBuilder(
        column: $table.mode,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnFilters<DateTime> get changedAt => $composableBuilder(
    column: $table.changedAt,
    builder: (column) => ColumnFilters(column),
  );

  $$WinterArcSessionsTableFilterComposer get sessionId {
    final $$WinterArcSessionsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.sessionId,
      referencedTable: $db.winterArcSessions,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$WinterArcSessionsTableFilterComposer(
            $db: $db,
            $table: $db.winterArcSessions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$DayModesTableOrderingComposer
    extends Composer<_$AppDatabase, $DayModesTable> {
  $$DayModesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get date => $composableBuilder(
    column: $table.date,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get mode => $composableBuilder(
    column: $table.mode,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get changedAt => $composableBuilder(
    column: $table.changedAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$WinterArcSessionsTableOrderingComposer get sessionId {
    final $$WinterArcSessionsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.sessionId,
      referencedTable: $db.winterArcSessions,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$WinterArcSessionsTableOrderingComposer(
            $db: $db,
            $table: $db.winterArcSessions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$DayModesTableAnnotationComposer
    extends Composer<_$AppDatabase, $DayModesTable> {
  $$DayModesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumnWithTypeConverter<LocalDate, String> get date =>
      $composableBuilder(column: $table.date, builder: (column) => column);

  GeneratedColumnWithTypeConverter<DayMode, String> get mode =>
      $composableBuilder(column: $table.mode, builder: (column) => column);

  GeneratedColumn<DateTime> get changedAt =>
      $composableBuilder(column: $table.changedAt, builder: (column) => column);

  $$WinterArcSessionsTableAnnotationComposer get sessionId {
    final $$WinterArcSessionsTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.sessionId,
          referencedTable: $db.winterArcSessions,
          getReferencedColumn: (t) => t.id,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$WinterArcSessionsTableAnnotationComposer(
                $db: $db,
                $table: $db.winterArcSessions,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return composer;
  }
}

class $$DayModesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $DayModesTable,
          DayModeRow,
          $$DayModesTableFilterComposer,
          $$DayModesTableOrderingComposer,
          $$DayModesTableAnnotationComposer,
          $$DayModesTableCreateCompanionBuilder,
          $$DayModesTableUpdateCompanionBuilder,
          (DayModeRow, $$DayModesTableReferences),
          DayModeRow,
          PrefetchHooks Function({bool sessionId})
        > {
  $$DayModesTableTableManager(_$AppDatabase db, $DayModesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$DayModesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$DayModesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$DayModesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> sessionId = const Value.absent(),
                Value<LocalDate> date = const Value.absent(),
                Value<DayMode> mode = const Value.absent(),
                Value<DateTime> changedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => DayModesCompanion(
                sessionId: sessionId,
                date: date,
                mode: mode,
                changedAt: changedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required int sessionId,
                required LocalDate date,
                required DayMode mode,
                required DateTime changedAt,
                Value<int> rowid = const Value.absent(),
              }) => DayModesCompanion.insert(
                sessionId: sessionId,
                date: date,
                mode: mode,
                changedAt: changedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$DayModesTable, DayModeRow>(table),
                  $$DayModesTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({sessionId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (sessionId) {
                      state = state.withJoin(
                        currentTable: table,
                        currentColumn: table.sessionId,
                        referencedTable: $$DayModesTableReferences
                            ._sessionIdTable(db),
                        referencedColumn: $$DayModesTableReferences
                            ._sessionIdTable(db)
                            .id,
                      ) as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$DayModesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $DayModesTable,
      DayModeRow,
      $$DayModesTableFilterComposer,
      $$DayModesTableOrderingComposer,
      $$DayModesTableAnnotationComposer,
      $$DayModesTableCreateCompanionBuilder,
      $$DayModesTableUpdateCompanionBuilder,
      (DayModeRow, $$DayModesTableReferences),
      DayModeRow,
      PrefetchHooks Function({bool sessionId})
    >;
typedef $$AchievementUnlocksTableCreateCompanionBuilder =
    AchievementUnlocksCompanion Function({
      required int sessionId,
      required String achievementKey,
      required LocalDate unlockedOn,
      required DateTime unlockedAt,
      Value<int> rowid,
    });
typedef $$AchievementUnlocksTableUpdateCompanionBuilder =
    AchievementUnlocksCompanion Function({
      Value<int> sessionId,
      Value<String> achievementKey,
      Value<LocalDate> unlockedOn,
      Value<DateTime> unlockedAt,
      Value<int> rowid,
    });

final class $$AchievementUnlocksTableReferences
    extends
        BaseReferences<
          _$AppDatabase,
          $AchievementUnlocksTable,
          AchievementUnlockRow
        > {
  $$AchievementUnlocksTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $WinterArcSessionsTable _sessionIdTable(_$AppDatabase db) => db
      .winterArcSessions
      .createAlias('achievement_unlocks__session_id__winter_arc_sessions__id');

  $$WinterArcSessionsTableProcessedTableManager get sessionId {
    final $_column = $_itemColumn<int>('session_id')!;

    final manager = $$WinterArcSessionsTableTableManager(
      $_db,
      $_db.winterArcSessions,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_sessionIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$AchievementUnlocksTableFilterComposer
    extends Composer<_$AppDatabase, $AchievementUnlocksTable> {
  $$AchievementUnlocksTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get achievementKey => $composableBuilder(
    column: $table.achievementKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<LocalDate, LocalDate, String> get unlockedOn =>
      $composableBuilder(
        column: $table.unlockedOn,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnFilters<DateTime> get unlockedAt => $composableBuilder(
    column: $table.unlockedAt,
    builder: (column) => ColumnFilters(column),
  );

  $$WinterArcSessionsTableFilterComposer get sessionId {
    final $$WinterArcSessionsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.sessionId,
      referencedTable: $db.winterArcSessions,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$WinterArcSessionsTableFilterComposer(
            $db: $db,
            $table: $db.winterArcSessions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$AchievementUnlocksTableOrderingComposer
    extends Composer<_$AppDatabase, $AchievementUnlocksTable> {
  $$AchievementUnlocksTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get achievementKey => $composableBuilder(
    column: $table.achievementKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get unlockedOn => $composableBuilder(
    column: $table.unlockedOn,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get unlockedAt => $composableBuilder(
    column: $table.unlockedAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$WinterArcSessionsTableOrderingComposer get sessionId {
    final $$WinterArcSessionsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.sessionId,
      referencedTable: $db.winterArcSessions,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$WinterArcSessionsTableOrderingComposer(
            $db: $db,
            $table: $db.winterArcSessions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$AchievementUnlocksTableAnnotationComposer
    extends Composer<_$AppDatabase, $AchievementUnlocksTable> {
  $$AchievementUnlocksTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get achievementKey => $composableBuilder(
    column: $table.achievementKey,
    builder: (column) => column,
  );

  GeneratedColumnWithTypeConverter<LocalDate, String> get unlockedOn =>
      $composableBuilder(
        column: $table.unlockedOn,
        builder: (column) => column,
      );

  GeneratedColumn<DateTime> get unlockedAt => $composableBuilder(
    column: $table.unlockedAt,
    builder: (column) => column,
  );

  $$WinterArcSessionsTableAnnotationComposer get sessionId {
    final $$WinterArcSessionsTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.sessionId,
          referencedTable: $db.winterArcSessions,
          getReferencedColumn: (t) => t.id,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$WinterArcSessionsTableAnnotationComposer(
                $db: $db,
                $table: $db.winterArcSessions,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return composer;
  }
}

class $$AchievementUnlocksTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $AchievementUnlocksTable,
          AchievementUnlockRow,
          $$AchievementUnlocksTableFilterComposer,
          $$AchievementUnlocksTableOrderingComposer,
          $$AchievementUnlocksTableAnnotationComposer,
          $$AchievementUnlocksTableCreateCompanionBuilder,
          $$AchievementUnlocksTableUpdateCompanionBuilder,
          (AchievementUnlockRow, $$AchievementUnlocksTableReferences),
          AchievementUnlockRow,
          PrefetchHooks Function({bool sessionId})
        > {
  $$AchievementUnlocksTableTableManager(
    _$AppDatabase db,
    $AchievementUnlocksTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$AchievementUnlocksTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$AchievementUnlocksTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$AchievementUnlocksTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<int> sessionId = const Value.absent(),
                Value<String> achievementKey = const Value.absent(),
                Value<LocalDate> unlockedOn = const Value.absent(),
                Value<DateTime> unlockedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => AchievementUnlocksCompanion(
                sessionId: sessionId,
                achievementKey: achievementKey,
                unlockedOn: unlockedOn,
                unlockedAt: unlockedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required int sessionId,
                required String achievementKey,
                required LocalDate unlockedOn,
                required DateTime unlockedAt,
                Value<int> rowid = const Value.absent(),
              }) => AchievementUnlocksCompanion.insert(
                sessionId: sessionId,
                achievementKey: achievementKey,
                unlockedOn: unlockedOn,
                unlockedAt: unlockedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$AchievementUnlocksTable, AchievementUnlockRow>(
                    table,
                  ),
                  $$AchievementUnlocksTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({sessionId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (sessionId) {
                      state = state.withJoin(
                        currentTable: table,
                        currentColumn: table.sessionId,
                        referencedTable: $$AchievementUnlocksTableReferences
                            ._sessionIdTable(db),
                        referencedColumn: $$AchievementUnlocksTableReferences
                            ._sessionIdTable(db)
                            .id,
                      ) as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$AchievementUnlocksTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $AchievementUnlocksTable,
      AchievementUnlockRow,
      $$AchievementUnlocksTableFilterComposer,
      $$AchievementUnlocksTableOrderingComposer,
      $$AchievementUnlocksTableAnnotationComposer,
      $$AchievementUnlocksTableCreateCompanionBuilder,
      $$AchievementUnlocksTableUpdateCompanionBuilder,
      (AchievementUnlockRow, $$AchievementUnlocksTableReferences),
      AchievementUnlockRow,
      PrefetchHooks Function({bool sessionId})
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$WinterArcSessionsTableTableManager get winterArcSessions =>
      $$WinterArcSessionsTableTableManager(_db, _db.winterArcSessions);
  $$HabitsTableTableManager get habits =>
      $$HabitsTableTableManager(_db, _db.habits);
  $$DailyHabitProgressEntriesTableTableManager get dailyHabitProgressEntries =>
      $$DailyHabitProgressEntriesTableTableManager(
        _db,
        _db.dailyHabitProgressEntries,
      );
  $$XpTransactionsTableTableManager get xpTransactions =>
      $$XpTransactionsTableTableManager(_db, _db.xpTransactions);
  $$HabitRevisionsTableTableManager get habitRevisions =>
      $$HabitRevisionsTableTableManager(_db, _db.habitRevisions);
  $$DayModesTableTableManager get dayModes =>
      $$DayModesTableTableManager(_db, _db.dayModes);
  $$AchievementUnlocksTableTableManager get achievementUnlocks =>
      $$AchievementUnlocksTableTableManager(_db, _db.achievementUnlocks);
}
