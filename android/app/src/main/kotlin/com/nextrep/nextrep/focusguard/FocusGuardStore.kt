package com.nextrep.nextrep.focusguard

import java.time.LocalDate

/**
 * Runs SQL against NextRep's database. Android uses SQLiteDatabase
 * ([AndroidSqlRunner]); JVM tests use a JDBC SQLite driver with the same SQL.
 *
 * Query rows hold Long, String or null.
 */
interface SqlRunner {
    fun query(sql: String, args: List<Any?>): List<List<Any?>>

    /** Runs one statement and returns the number of rows it changed. */
    fun update(sql: String, args: List<Any?>): Int
}

/** Focus Guard's stored configuration, as the worker needs it. */
data class FocusGuardConfig(
    val enabled: Boolean,
    val dailyBudgetMinutes: Int,
    /** `YYYY-MM-DD`, or null if Focus Guard never nudged. */
    val lastNudgedOn: String?,
    /** In the user's order. */
    val packages: List<String>,
)

/** The stored data doesn't follow Drift's rules: nothing is decided on it. */
class UnreadableConfigException(message: String) : Exception(message)

/**
 * Focus Guard's rows in Drift's schema-v6 database, read and claimed by the
 * background check. The schema and representation are Drift's (see
 * `lib/core/database/tables.dart`):
 *
 * - `focus_guard_preferences`: the single row `id = 1`; `enabled` INTEGER
 *   0 / 1; `daily_budget_minutes` INTEGER 1–1440; `last_nudged_on` TEXT
 *   `YYYY-MM-DD` or NULL (`LocalDateConverter`); `updated_at` INTEGER Unix
 *   seconds.
 * - `focus_guard_selected_apps`: `package_name` TEXT, `sort_order` INTEGER,
 *   `selected_at` INTEGER Unix seconds.
 *
 * The only write is [claim], to `last_nudged_on`; the schema and every other
 * value are left alone. No usage amount is ever written. A claim is never
 * reverted from here: only a restore (which turns Focus Guard off) clears it.
 */
class FocusGuardStore(private val sql: SqlRunner) {
    /** Drift's `PRAGMA user_version`: the schema the rows follow. */
    fun schemaVersion(): Long =
        sql.query("PRAGMA user_version", emptyList()).single().single() as Long

    /**
     * The configuration, or null if the user never saved one (Focus Guard is
     * off). One statement, so it reads a consistent snapshot even while the
     * app saves. Throws [UnreadableConfigException] for values Drift would
     * never have written.
     */
    fun load(): FocusGuardConfig? {
        val rows = sql.query(LOAD_SQL, emptyList())
        if (rows.isEmpty()) return null
        val first = rows.first()
        val enabled = when (first[0]) {
            0L -> false
            1L -> true
            else -> throw UnreadableConfigException("enabled")
        }
        val budget = (first[1] as? Long)
            ?.takeIf { it in MIN_BUDGET_MINUTES..MAX_BUDGET_MINUTES }
            ?: throw UnreadableConfigException("daily_budget_minutes")
        val lastNudgedOn = when (val value = first[2]) {
            null -> null
            is String -> value.takeIf { ISO_DATE.matches(it) }
                ?: throw UnreadableConfigException("last_nudged_on")
            else -> throw UnreadableConfigException("last_nudged_on")
        }
        val packages = rows.mapNotNull { it[3] }.map {
            (it as? String)?.takeIf { name -> PACKAGE_NAME.matches(name) }
                ?: throw UnreadableConfigException("package_name")
        }
        return FocusGuardConfig(enabled, budget.toInt(), lastNudgedOn, packages)
    }

    /**
     * Records [today] as the day's nudge, atomically, and returns whether this
     * call did it. One UPDATE that only matches while Focus Guard is still on
     * with the same budget and exactly the same apps that were measured, and
     * no nudge is recorded for [today] or later. A concurrent or repeated
     * check, a restore (which turns Focus Guard off) or a settings change in
     * between makes it match nothing.
     *
     * Claims only move forward: a stale check (one that measured an earlier
     * day) can never replace a newer date and so make that day eligible
     * again. A stored date more than a day ahead can only come from a clock
     * that was wrong when it was written, and is replaced, so a corrected
     * clock never blocks Focus Guard.
     */
    fun claim(today: String, budgetMinutes: Int, packages: Set<String>): Boolean {
        require(ISO_DATE.matches(today))
        require(packages.isNotEmpty())
        val tomorrow = LocalDate.parse(today).plusDays(1).toString()
        val placeholders = packages.joinToString(",") { "?" }
        val changed = sql.update(
            """
            UPDATE focus_guard_preferences SET last_nudged_on = ?
            WHERE id = 1 AND enabled = 1 AND daily_budget_minutes = ?
              AND (last_nudged_on IS NULL OR last_nudged_on < ? OR last_nudged_on > ?)
              AND (SELECT COUNT(*) FROM focus_guard_selected_apps) = ?
              AND NOT EXISTS (
                SELECT 1 FROM focus_guard_selected_apps
                WHERE package_name NOT IN ($placeholders))
            """.trimIndent(),
            listOf<Any?>(today, budgetMinutes.toLong(), today, tomorrow, packages.size.toLong()) +
                packages.toList(),
        )
        return changed == 1
    }

    companion object {
        /**
         * Whether [lastNudgedOn] already covers [today]: today, or tomorrow (a
         * nudge recorded before a westward time-zone change). The same rule
         * as [claim], which never claims such a day.
         */
        fun alreadyNudged(lastNudgedOn: String?, today: LocalDate): Boolean =
            lastNudgedOn != null &&
                lastNudgedOn >= today.toString() &&
                lastNudgedOn <= today.plusDays(1).toString()

        /** The Drift schema these statements are written for. */
        const val SCHEMA_VERSION = 6L

        // FocusGuardRules in lib/domain/focus_guard/focus_guard_settings.dart.
        const val MIN_BUDGET_MINUTES = 1L
        const val MAX_BUDGET_MINUTES = 1440L

        private val ISO_DATE = Regex("""^\d{4}-\d{2}-\d{2}$""")

        // LaunchableApps.isPackageName in lib/domain/focus_guard/launchable_apps.dart.
        private val PACKAGE_NAME = Regex("""^[A-Za-z][A-Za-z0-9_]*(\.[A-Za-z][A-Za-z0-9_]*)+$""")

        private val LOAD_SQL =
            """
            SELECT p.enabled, p.daily_budget_minutes, p.last_nudged_on, a.package_name
            FROM focus_guard_preferences p
            LEFT JOIN focus_guard_selected_apps a ON 1 = 1
            WHERE p.id = 1
            ORDER BY a.sort_order
            """.trimIndent()
    }
}
