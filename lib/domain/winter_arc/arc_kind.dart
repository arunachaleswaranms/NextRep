import '../../core/time/local_date.dart';

/// What kind of Winter Arc a session is. Persisted by [name] (schema v5,
/// backup format 2), so never rename values.
///
/// The kind is stored, never inferred from dates: a rolling arc that
/// happens to start on 1 October is still a rolling arc.
enum ArcKind {
  /// 92 calendar days from the day the user presses Start.
  rolling92,

  /// The fixed season, 1 October through 31 December of one year. Day 1 is
  /// always 1 October, whenever the user joins.
  seasonalWinter;

  bool get isSeasonal => this == ArcKind.seasonalWinter;
}

/// Where the Seasonal Winter Arc of a year stands on a given date.
enum SeasonPhase {
  /// 1 January – 31 August: the season can only be previewed.
  closed,

  /// 1 – 30 September: the season can be set up ahead of time, but not
  /// started.
  preseason,

  /// 1 October – 31 December: the season is running and can be joined.
  inSeason,
}

/// The Seasonal Winter Arc on one date of the device's local calendar.
final class SeasonAvailability {
  const SeasonAvailability._(this.phase, this.year);

  final SeasonPhase phase;

  /// The calendar year whose season this is about.
  final int year;

  /// 1 October of [year].
  LocalDate get seasonStart => SeasonalWinterRules.startOf(year);

  /// 31 December of [year].
  LocalDate get seasonEnd => SeasonalWinterRules.endOf(year);

  /// 1 September of [year], when setup opens.
  LocalDate get preseasonOpens =>
      LocalDate(year, SeasonalWinterRules.preseasonMonth, 1);

  /// Whether a setup for this season may be created now.
  bool get canSetUp => phase != SeasonPhase.closed;

  /// Whether a setup for this season may be started now.
  bool get canStart => phase == SeasonPhase.inSeason;

  @override
  bool operator ==(Object other) =>
      other is SeasonAvailability && other.phase == phase && other.year == year;

  @override
  int get hashCode => Object.hash(phase, year);

  @override
  String toString() => 'SeasonAvailability(${phase.name}, $year)';
}

/// The fixed calendar of the Seasonal Winter Arc.
abstract final class SeasonalWinterRules {
  static const int startMonth = 10;
  static const int endMonth = 12;
  static const int endDay = 31;

  /// Setup opens on the first of this month.
  static const int preseasonMonth = 9;

  /// 1 October of [year]: Day 1 of that season.
  static LocalDate startOf(int year) => LocalDate(year, startMonth, 1);

  /// 31 December of [year]: Day 92 of that season.
  static LocalDate endOf(int year) => LocalDate(year, endMonth, endDay);

  /// The season of [today]'s local calendar year and where it stands.
  static SeasonAvailability availabilityOn(LocalDate today) {
    final phase = switch (today.month) {
      < preseasonMonth => SeasonPhase.closed,
      preseasonMonth => SeasonPhase.preseason,
      _ => SeasonPhase.inSeason,
    };
    return SeasonAvailability._(phase, today.year);
  }

  /// Whether [start]..[end] is exactly one year's season window.
  static bool isSeasonWindow(LocalDate start, LocalDate end) =>
      start == startOf(start.year) && end == endOf(start.year);
}
