package com.nextrep.nextrep.focusguard

import android.content.Context
import android.database.Cursor
import android.database.sqlite.SQLiteDatabase
import android.os.Build
import java.io.File

/**
 * Opens the app's own Drift database for the background check.
 *
 * The file is Drift's (`AppDatabase.open()`: `driftDatabase(name: 'nextrep')`
 * in path_provider's documents directory, `Context.getDir("flutter")`), so
 * there is one store of Focus Guard settings for the UI and the worker.
 *
 * Only ever opened in the `:focus_guard` process ([FocusGuardCheckProvider]),
 * never in the app's main process. Drift uses its own bundled SQLite; two
 * SQLite libraries in one process don't see each other's file locks and can
 * corrupt a database (sqlite.org/howtocorrupt.html, 2.2.1). Across processes
 * the ordinary SQLite locking keeps the two safe.
 *
 * Opened read-write without CREATE (a missing database is never created),
 * with NO_LOCALIZED_COLLATORS (no `android_metadata` table is added) and an
 * explicit rollback journal, Drift's own mode (no compatibility WAL). The
 * schema is never changed, and a database that isn't schema v6 is left alone.
 */
object FocusGuardDatabase {
    /** Relative to the app's data directory. */
    const val RELATIVE_PATH = "app_flutter/nextrep.sqlite"

    fun file(context: Context): File = File(context.dataDir, RELATIVE_PATH)

    /** Runs [block] on the open database, or returns null if there is none to use. */
    fun <T> withStore(context: Context, block: (FocusGuardStore) -> T): T? {
        val file = file(context)
        if (!file.isFile) return null
        val flags = SQLiteDatabase.OPEN_READWRITE or SQLiteDatabase.NO_LOCALIZED_COLLATORS
        val db = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            SQLiteDatabase.openDatabase(
                file,
                SQLiteDatabase.OpenParams.Builder()
                    .setOpenFlags(flags)
                    .setJournalMode("DELETE")
                    .build(),
            )
        } else {
            SQLiteDatabase.openDatabase(file.path, null, flags)
        }
        return db.use {
            val store = FocusGuardStore(AndroidSqlRunner(it))
            if (store.schemaVersion() != FocusGuardStore.SCHEMA_VERSION) null else block(store)
        }
    }
}

/** [SqlRunner] over an Android [SQLiteDatabase]. Android sets a busy timeout. */
class AndroidSqlRunner(private val db: SQLiteDatabase) : SqlRunner {
    override fun query(sql: String, args: List<Any?>): List<List<Any?>> {
        require(args.isEmpty()) { "Queries take no arguments" }
        return db.rawQuery(sql, null).use { cursor ->
            val rows = ArrayList<List<Any?>>()
            while (cursor.moveToNext()) {
                rows.add(
                    (0 until cursor.columnCount).map { i ->
                        when (cursor.getType(i)) {
                            Cursor.FIELD_TYPE_NULL -> null
                            Cursor.FIELD_TYPE_INTEGER -> cursor.getLong(i)
                            Cursor.FIELD_TYPE_STRING -> cursor.getString(i)
                            else -> UNSUPPORTED
                        }
                    },
                )
            }
            rows
        }
    }

    override fun update(sql: String, args: List<Any?>): Int =
        db.compileStatement(sql).use { statement ->
            args.forEachIndexed { i, arg ->
                when (arg) {
                    null -> statement.bindNull(i + 1)
                    is Long -> statement.bindLong(i + 1, arg)
                    is String -> statement.bindString(i + 1, arg)
                    else -> throw IllegalArgumentException("Unsupported argument type")
                }
            }
            statement.executeUpdateDelete()
        }

    private companion object {
        /** A value of a type Drift never writes to these columns. */
        val UNSUPPORTED = Any()
    }
}
