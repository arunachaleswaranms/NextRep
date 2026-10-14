package com.nextrep.nextrep.focusguard

import android.content.Context
import android.content.pm.ApplicationInfo
import android.util.Log
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.PeriodicWorkRequest
import androidx.work.WorkManager
import androidx.work.Worker
import androidx.work.WorkerParameters
import java.util.concurrent.TimeUnit

/**
 * The periodic Focus Guard check: a plain native Worker, with no Flutter
 * engine or Dart isolate, no foreground service and no network. It hands
 * the check to [FocusGuardCheckProvider] in the `:focus_guard` process and
 * always succeeds, so a failure never turns into retries; the next period
 * simply checks again.
 */
class FocusGuardWorker(context: Context, params: WorkerParameters) : Worker(context, params) {
    override fun doWork(): Result {
        val context = applicationContext
        val outcome = try {
            context.contentResolver
                .call(
                    FocusGuardCheckProvider.uri(context),
                    FocusGuardCheckProvider.METHOD_CHECK,
                    null,
                    null,
                )
                ?.getString(FocusGuardCheckProvider.KEY_OUTCOME)
        } catch (e: Exception) {
            null
        }
        // The outcome names a decision only (never an app or an amount), and
        // only debuggable builds log it.
        if (context.applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE != 0) {
            Log.d(TAG, "check: ${outcome ?: "unavailable"}")
        }
        return Result.success()
    }

    private companion object {
        const val TAG = "FocusGuard"
    }
}

/**
 * The one unique periodic Focus Guard job. Android runs it about every 15
 * minutes at best, and may run it much later (Doze, standby buckets, job
 * batching); after a force-stop, not at all until NextRep is opened again.
 * WorkManager reschedules it after a reboot by itself.
 */
object FocusGuardScheduler {
    const val UNIQUE_WORK = "focus_guard_check"
    private const val INTERVAL_MINUTES = 15L

    /** Idempotent: an existing job keeps its timing (KEEP). */
    fun ensureScheduled(context: Context) {
        WorkManager.getInstance(context)
            .enqueueUniquePeriodicWork(
                UNIQUE_WORK,
                ExistingPeriodicWorkPolicy.KEEP,
                PeriodicWorkRequest.Builder(
                    FocusGuardWorker::class.java,
                    INTERVAL_MINUTES,
                    TimeUnit.MINUTES,
                ).build(),
            )
            .result
            .get()
    }

    fun cancel(context: Context) {
        WorkManager.getInstance(context).cancelUniqueWork(UNIQUE_WORK).result.get()
    }
}
