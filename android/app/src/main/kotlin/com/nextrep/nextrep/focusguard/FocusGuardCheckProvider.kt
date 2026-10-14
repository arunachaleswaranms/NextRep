package com.nextrep.nextrep.focusguard

import android.content.ContentProvider
import android.content.ContentValues
import android.content.Context
import android.database.Cursor
import android.net.Uri
import android.os.Binder
import android.os.Bundle
import android.os.Process
import java.time.ZoneId

/**
 * Runs the background check in the `:focus_guard` process, the only process
 * that opens NextRep's database with Android's SQLite (see
 * [FocusGuardDatabase]). Not exported: only NextRep's own worker calls it,
 * through [ContentProvider.call]. It has no data to query and starts no
 * Flutter engine.
 */
class FocusGuardCheckProvider : ContentProvider() {
    override fun onCreate(): Boolean = true

    override fun call(method: String, arg: String?, extras: Bundle?): Bundle? {
        if (method != METHOD_CHECK) return null
        if (Binder.getCallingUid() != Process.myUid()) throw SecurityException()
        val context = context ?: return null
        val outcome = synchronized(lock) { check(context) }
        return Bundle().apply { putString(KEY_OUTCOME, outcome.name) }
    }

    private fun check(context: Context): CheckOutcome =
        try {
            FocusGuardDatabase.withStore(context) { store ->
                FocusGuardCheck(store, AndroidCheckPlatform(context)).run()
            } ?: CheckOutcome.STORE_UNAVAILABLE
        } catch (e: Exception) {
            // Locked, missing or unreadable: no nudge, try again next period.
            CheckOutcome.STORE_UNAVAILABLE
        }

    override fun query(
        uri: Uri,
        projection: Array<out String>?,
        selection: String?,
        selectionArgs: Array<out String>?,
        sortOrder: String?,
    ): Cursor? = null

    override fun getType(uri: Uri): String? = null

    override fun insert(uri: Uri, values: ContentValues?): Uri? = null

    override fun delete(uri: Uri, selection: String?, selectionArgs: Array<out String>?): Int = 0

    override fun update(
        uri: Uri,
        values: ContentValues?,
        selection: String?,
        selectionArgs: Array<out String>?,
    ): Int = 0

    companion object {
        const val METHOD_CHECK = "check"
        const val KEY_OUTCOME = "outcome"

        private val lock = Any()

        fun uri(context: Context): Uri = Uri.parse("content://${context.packageName}.focusguard")
    }
}

private class AndroidCheckPlatform(private val context: Context) : CheckPlatform {
    override fun nowMillis(): Long = System.currentTimeMillis()

    override fun zone(): ZoneId = ZoneId.systemDefault()

    override fun usageAccessGranted(): Boolean = FocusGuardUsage.usageAccessGranted(context)

    override fun foregroundMillis(
        packages: Set<String>,
        windowStart: Long,
        windowEnd: Long,
    ): Map<String, Long> = FocusGuardUsage.foregroundMillis(context, packages, windowStart, windowEnd)

    override fun nudgesAllowed(): Boolean = FocusGuardNotifier.nudgesAllowed(context)

    override fun prepareNudge(budgetMinutes: Int): PreparedNudge =
        FocusGuardNotifier.prepare(context, budgetMinutes)
}
