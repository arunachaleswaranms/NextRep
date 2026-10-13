package com.nextrep.nextrep.feasibility

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.workDataOf
import java.util.concurrent.TimeUnit

// PHASE 11A FEASIBILITY PROBE (debug only, temporary). Driven from adb:
//   adb shell am broadcast -n com.nextrep.nextrep.feasibility/com.nextrep.nextrep.feasibility.FocusGuardProbeReceiver --es cmd status
class FocusGuardProbeReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        val pending = goAsync()
        Thread {
            try {
                handle(context.applicationContext, intent)
            } catch (t: Throwable) {
                FocusGuardProbe.log("error ${t.javaClass.simpleName}: ${t.message}")
            } finally {
                pending.finish()
            }
        }.start()
    }

    private fun handle(ctx: Context, intent: Intent) {
        val packages = intent.getStringExtra("pkgs")
            ?.split(',')?.filter { it.isNotBlank() }?.toSet().orEmpty()
        when (intent.getStringExtra("cmd")) {
            "status" -> FocusGuardProbe.log(
                "status sdk=${Build.VERSION.SDK_INT} access=${FocusGuardProbe.usageAccessGranted(ctx)} " +
                    "notifications=${FocusGuardProbe.notificationsEnabled(ctx)}",
            )

            "open_settings" -> {
                val settings = FocusGuardProbe.usageAccessSettingsIntent(ctx)
                val resolves = settings.resolveActivity(ctx.packageManager) != null
                FocusGuardProbe.log("open_settings resolves=$resolves")
                ctx.startActivity(settings)
            }

            "apps" -> {
                val d = FocusGuardProbe.discover(ctx)
                val expect = intent.getStringExtra("expect")
                    ?.split(',')?.filter { it.isNotBlank() }.orEmpty()
                val internal = intent.getStringExtra("internal")
                    ?.split(',')?.filter { it.isNotBlank() }.orEmpty()
                FocusGuardProbe.log(
                    "apps launcherApps=${d.launcherAppsPackages.size} " +
                        "queryIntentActivities=${d.queryIntentPackages.size} " +
                        "visibleInstalled=${d.visibleInstalledPackages} " +
                        "includesSelf=${ctx.packageName in d.launcherAppsPackages} " +
                        "launcherAppsMs=${d.launcherAppsMs}",
                )
                expect.forEachIndexed { i, p ->
                    FocusGuardProbe.log(
                        "apps expected#$i launcherApps=${p in d.launcherAppsPackages} " +
                            "queryIntent=${p in d.queryIntentPackages}",
                    )
                }
                internal.forEachIndexed { i, p ->
                    FocusGuardProbe.log(
                        "apps internal#$i launcherApps=${p in d.launcherAppsPackages} " +
                            "queryIntent=${p in d.queryIntentPackages}",
                    )
                }
            }

            "usage" -> {
                val access = FocusGuardProbe.usageAccessGranted(ctx)
                val u = FocusGuardProbe.usage(ctx, packages)
                FocusGuardProbe.log(
                    "usage access=$access rawEvents=${u.rawEventCount} rawStats=${u.rawStatsCount} " +
                        "elapsedMs=${u.elapsedMs}",
                )
                packages.forEachIndexed { i, p ->
                    FocusGuardProbe.log(
                        "usage test#$i eventsS=${(u.eventsMs[p] ?: 0) / 1000} " +
                            "aggForegroundS=${(u.aggregateForegroundMs[p] ?: 0) / 1000} " +
                            "aggVisibleS=${(u.aggregateVisibleMs[p] ?: 0) / 1000}",
                    )
                }
            }

            "work_once" -> {
                val request = OneTimeWorkRequestBuilder<FocusGuardProbeWorker>()
                    .setInputData(workDataOf(FocusGuardProbeWorker.KEY_PACKAGES to packages.joinToString(",")))
                    .addTag("probe-once")
                    .build()
                WorkManager.getInstance(ctx).enqueue(request)
                FocusGuardProbe.log("work_once enqueued id=${request.id}")
            }

            "work_periodic" -> {
                val request = PeriodicWorkRequestBuilder<FocusGuardProbeWorker>(15, TimeUnit.MINUTES)
                    .setInputData(workDataOf(FocusGuardProbeWorker.KEY_PACKAGES to packages.joinToString(",")))
                    .addTag("probe-periodic")
                    .build()
                WorkManager.getInstance(ctx).enqueueUniquePeriodicWork(
                    PERIODIC, ExistingPeriodicWorkPolicy.KEEP, request,
                )
                FocusGuardProbe.log("work_periodic enqueued KEEP interval=15m")
            }

            "work_cancel" -> {
                WorkManager.getInstance(ctx).cancelUniqueWork(PERIODIC).result.get()
                FocusGuardProbe.log("work_cancel done")
            }

            "work_state" -> {
                val infos = WorkManager.getInstance(ctx).getWorkInfosForUniqueWork(PERIODIC).get()
                infos.forEach {
                    FocusGuardProbe.log(
                        "work_state periodic state=${it.state} runAttempt=${it.runAttemptCount} " +
                            "nextScheduleMs=${it.nextScheduleTimeMillis}",
                    )
                }
                if (infos.isEmpty()) FocusGuardProbe.log("work_state periodic none")
                val prefs = ctx.getSharedPreferences(FocusGuardProbeWorker.PREFS, Context.MODE_PRIVATE)
                FocusGuardProbe.log(
                    "work_state diag runs=${prefs.getInt("runs", 0)} " +
                        "lastRunMs=${prefs.getLong("last_run_ms", 0)} " +
                        "lastAccess=${prefs.getBoolean("last_access", false)} " +
                        "lastCompleted=${prefs.getBoolean("last_completed", false)}",
                )
            }

            else -> FocusGuardProbe.log("unknown cmd")
        }
    }

    companion object {
        const val PERIODIC = "focus-guard-probe"
    }
}
