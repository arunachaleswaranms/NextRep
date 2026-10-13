package com.nextrep.nextrep.feasibility

import android.content.Context
import androidx.work.Worker
import androidx.work.WorkerParameters

// PHASE 11A FEASIBILITY PROBE (debug only, temporary). Plain native worker:
// no Flutter engine, no Dart isolate, no foreground service. Records only
// non-sensitive diagnostics (when it ran, whether access was available).
class FocusGuardProbeWorker(context: Context, params: WorkerParameters) :
    Worker(context, params) {

    override fun doWork(): Result {
        val t0 = System.nanoTime()
        val ctx = applicationContext
        val access = FocusGuardProbe.usageAccessGranted(ctx)
        val notifications = FocusGuardProbe.notificationsEnabled(ctx)
        val packages = inputData.getString(KEY_PACKAGES)
            ?.split(',')?.filter { it.isNotBlank() }?.toSet().orEmpty()
        var measured = "skipped"
        if (access && packages.isNotEmpty()) {
            val usage = FocusGuardProbe.usage(ctx, packages)
            measured = "nonzero=${usage.eventsMs.values.sum() > 0} " +
                "testSeconds=${usage.eventsMs.values.sum() / 1000}"
        } else if (!access) {
            measured = "no-op (usage access unavailable)"
        }
        val elapsed = (System.nanoTime() - t0) / 1_000_000
        val prefs = ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val runs = prefs.getInt("runs", 0) + 1
        prefs.edit()
            .putInt("runs", runs)
            .putLong("last_run_ms", System.currentTimeMillis())
            .putBoolean("last_access", access)
            .putBoolean("last_notifications", notifications)
            .putBoolean("last_completed", true)
            .putLong("last_elapsed_ms", elapsed)
            .apply()
        FocusGuardProbe.log(
            "worker run=$runs id=$id tags=$tags attempt=$runAttemptCount " +
                "access=$access notifications=$notifications $measured elapsedMs=$elapsed",
        )
        return Result.success()
    }

    companion object {
        const val KEY_PACKAGES = "packages"
        const val PREFS = "focus_guard_probe"
    }
}
