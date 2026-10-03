import 'package:drift/drift.dart';

import '../time/local_date.dart';

/// Stores [LocalDate] as ISO `YYYY-MM-DD` text, which sorts chronologically.
class LocalDateConverter extends TypeConverter<LocalDate, String> {
  const LocalDateConverter();

  @override
  LocalDate fromSql(String fromDb) => LocalDate.parse(fromDb);

  @override
  String toSql(LocalDate value) => value.toIsoString();
}
