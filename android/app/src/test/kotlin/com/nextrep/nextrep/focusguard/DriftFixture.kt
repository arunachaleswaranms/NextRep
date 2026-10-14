package com.nextrep.nextrep.focusguard

import java.io.File
import java.sql.Connection
import java.sql.DriverManager
import java.sql.Types

/**
 * A SQLite file with Focus Guard's tables exactly as Drift creates them at
 * schema v6 (`SELECT sql FROM sqlite_master`, captured from AppDatabase), and
 * Drift's value representation. Synthetic package names only.
 */
class DriftFixture(val file: File) {
    init {
        connect().use { c ->
            c.createStatement().use { s ->
                s.execute(
                    "CREATE TABLE \"focus_guard_preferences\" (\"id\" INTEGER NOT NULL CHECK(\"id\" = 1), " +
                        "\"enabled\" INTEGER NOT NULL CHECK (\"enabled\" IN (0, 1)), " +
                        "\"daily_budget_minutes\" INTEGER NOT NULL CHECK(\"daily_budget_minutes\" BETWEEN 1 AND 1440), " +
                        "\"last_nudged_on\" TEXT NULL, \"updated_at\" INTEGER NOT NULL, PRIMARY KEY (\"id\"))",
                )
                s.execute(
                    "CREATE TABLE \"focus_guard_selected_apps\" (\"package_name\" TEXT NOT NULL " +
                        "CHECK(LENGTH(\"package_name\") BETWEEN 3 AND 255), " +
                        "\"sort_order\" INTEGER NOT NULL CHECK(\"sort_order\" >= 0), " +
                        "\"selected_at\" INTEGER NOT NULL, PRIMARY KEY (\"package_name\"), UNIQUE (\"sort_order\"))",
                )
                s.execute("PRAGMA user_version = 6")
            }
        }
    }

    fun connect(): Connection = DriverManager.getConnection("jdbc:sqlite:${file.path}").apply {
        createStatement().use { it.execute("PRAGMA busy_timeout = 5000") }
    }

    /**
     * What `DriftFocusGuardSettingsRepository.save` does (Phase 11C): an
     * upsert that keeps a stored `last_nudged_on`, and the apps replaced in
     * one transaction.
     */
    fun save(
        enabled: Boolean,
        budget: Int,
        packages: List<String>,
        lastNudgedOnForNewRow: String? = null,
        updatedAt: Long = 1_791_201_600L,
    ) = connect().use { c ->
        c.autoCommit = false
        c.prepareStatement(
            "INSERT INTO focus_guard_preferences (id, enabled, daily_budget_minutes, last_nudged_on, updated_at) " +
                "VALUES (1, ?, ?, ?, ?) ON CONFLICT(id) DO UPDATE SET enabled = excluded.enabled, " +
                "daily_budget_minutes = excluded.daily_budget_minutes, updated_at = excluded.updated_at",
        ).use {
            it.setLong(1, if (enabled) 1 else 0)
            it.setLong(2, budget.toLong())
            if (lastNudgedOnForNewRow == null) it.setNull(3, Types.VARCHAR) else it.setString(3, lastNudgedOnForNewRow)
            it.setLong(4, updatedAt)
            it.executeUpdate()
        }
        c.createStatement().use { it.execute("DELETE FROM focus_guard_selected_apps") }
        packages.forEachIndexed { i, name ->
            c.prepareStatement(
                "INSERT INTO focus_guard_selected_apps (package_name, sort_order, selected_at) VALUES (?, ?, ?)",
            ).use {
                it.setString(1, name)
                it.setLong(2, i.toLong())
                it.setLong(3, updatedAt)
                it.executeUpdate()
            }
        }
        c.commit()
    }

    /** What `DriftBackupStore.replaceAll` does: configuration kept, off, no nudge. */
    fun restore(budget: Int, packages: List<String>) = connect().use { c ->
        c.autoCommit = false
        c.createStatement().use {
            it.execute("DELETE FROM focus_guard_selected_apps")
            it.execute("DELETE FROM focus_guard_preferences")
            it.execute(
                "INSERT INTO focus_guard_preferences (id, enabled, daily_budget_minutes, last_nudged_on, updated_at) " +
                    "VALUES (1, 0, $budget, NULL, 1791201600)",
            )
        }
        packages.forEachIndexed { i, name ->
            c.createStatement().use {
                it.execute(
                    "INSERT INTO focus_guard_selected_apps VALUES ('$name', $i, 1791201600)",
                )
            }
        }
        c.commit()
    }

    fun exec(sql: String) = connect().use { c -> c.createStatement().use { it.execute(sql) } }

    fun lastNudgedOn(): String? = connect().use { c ->
        c.createStatement().use { s ->
            s.executeQuery("SELECT last_nudged_on FROM focus_guard_preferences WHERE id = 1").use { rs ->
                if (rs.next()) rs.getString(1) else null
            }
        }
    }

    fun <T> withStore(block: (FocusGuardStore) -> T): T = connect().use { block(FocusGuardStore(JdbcSqlRunner(it))) }

    companion object {
        fun create(): DriftFixture {
            val file = File.createTempFile("nextrep", ".sqlite")
            file.delete()
            file.deleteOnExit()
            return DriftFixture(file)
        }
    }
}

/** [SqlRunner] over JDBC, normalising values like [AndroidSqlRunner]. */
class JdbcSqlRunner(private val connection: Connection) : SqlRunner {
    override fun query(sql: String, args: List<Any?>): List<List<Any?>> =
        connection.prepareStatement(sql).use { statement ->
            bind(statement, args)
            statement.executeQuery().use { rs ->
                val rows = ArrayList<List<Any?>>()
                val columns = rs.metaData.columnCount
                while (rs.next()) {
                    rows.add(
                        (1..columns).map { i ->
                            when (val value = rs.getObject(i)) {
                                null -> null
                                is Int -> value.toLong()
                                is Long, is String -> value
                                else -> value
                            }
                        },
                    )
                }
                rows
            }
        }

    override fun update(sql: String, args: List<Any?>): Int =
        connection.prepareStatement(sql).use { statement ->
            bind(statement, args)
            statement.executeUpdate()
        }

    private fun bind(statement: java.sql.PreparedStatement, args: List<Any?>) {
        args.forEachIndexed { i, arg ->
            when (arg) {
                null -> statement.setNull(i + 1, Types.VARCHAR)
                is Long -> statement.setLong(i + 1, arg)
                is String -> statement.setString(i + 1, arg)
                else -> throw IllegalArgumentException()
            }
        }
    }
}
