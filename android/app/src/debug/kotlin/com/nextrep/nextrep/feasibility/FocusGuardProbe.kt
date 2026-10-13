package com.nextrep.nextrep.feasibility

import android.app.AppOpsManager
import android.app.usage.UsageEvents
import android.app.usage.UsageStatsManager
import android.content.Context
import android.content.Intent
import android.content.pm.LauncherApps
import android.content.pm.PackageManager
import android.os.Build
import android.os.Process
import android.util.Log
import androidx.core.app.NotificationManagerCompat
import java.time.ZoneId
import java.time.ZonedDateTime

// PHASE 11A FEASIBILITY PROBE (debug source set only, temporary).
// Exercises the Android APIs Focus Guard would need. Logs counts, booleans
// and, for explicitly injected test packages only, foreground seconds.
// Persists nothing about usage.
object FocusGuardProbe {
    const val TAG = "NRProbe"

    fun usageAccessGranted(context: Context): Boolean {
        val appOps = context.getSystemService(AppOpsManager::class.java)
        val mode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            appOps.unsafeCheckOpNoThrow(
                AppOpsManager.OPSTR_GET_USAGE_STATS, Process.myUid(), context.packageName,
            )
        } else {
            @Suppress("DEPRECATION")
            appOps.checkOpNoThrow(
                AppOpsManager.OPSTR_GET_USAGE_STATS, Process.myUid(), context.packageName,
            )
        }
        return if (mode == AppOpsManager.MODE_DEFAULT) {
            context.checkCallingOrSelfPermission(android.Manifest.permission.PACKAGE_USAGE_STATS) ==
                PackageManager.PERMISSION_GRANTED
        } else {
            mode == AppOpsManager.MODE_ALLOWED
        }
    }

    fun notificationsEnabled(context: Context): Boolean =
        NotificationManagerCompat.from(context).areNotificationsEnabled()

    fun usageAccessSettingsIntent(context: Context): Intent =
        Intent(android.provider.Settings.ACTION_USAGE_ACCESS_SETTINGS).apply {
            // Android 10+ opens this app's own page; older versions ignore it.
            data = android.net.Uri.parse("package:${context.packageName}")
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }

    /** Local midnight of today in the current zone, and now. */
    fun todayWindow(): Pair<Long, Long> {
        val zone = ZoneId.systemDefault()
        val now = ZonedDateTime.now(zone)
        val start = now.toLocalDate().atStartOfDay(zone)
        return start.toInstant().toEpochMilli() to now.toInstant().toEpochMilli()
    }

    data class Discovery(
        val launcherAppsPackages: Set<String>,
        val queryIntentPackages: Set<String>,
        val visibleInstalledPackages: Int,
        val launcherAppsMs: Long,
    )

    fun discover(context: Context): Discovery {
        val t0 = System.nanoTime()
        val launcher = context.getSystemService(LauncherApps::class.java)
        val viaLauncher = launcher.getActivityList(null, Process.myUserHandle())
            .map { it.applicationInfo.packageName }
            .toSet()
        val elapsed = (System.nanoTime() - t0) / 1_000_000
        val pm = context.packageManager
        val intent = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)
        val viaQuery = pm.queryIntentActivities(intent, 0)
            .map { it.activityInfo.packageName }
            .toSet()
        val installed = pm.getInstalledPackages(0).size
        return Discovery(viaLauncher, viaQuery, installed, elapsed)
    }

    data class Usage(
        val eventsMs: Map<String, Long>,
        val aggregateForegroundMs: Map<String, Long>,
        val aggregateVisibleMs: Map<String, Long>,
        val rawEventCount: Int,
        val rawStatsCount: Int,
        val elapsedMs: Long,
    )

    /**
     * Foreground time today for [packages], three ways. Deliberately does NOT
     * check access first, so the probe can show what Android returns when
     * access is missing.
     */
    fun usage(context: Context, packages: Set<String>): Usage {
        val t0 = System.nanoTime()
        val (start, end) = todayWindow()
        val usm = context.getSystemService(UsageStatsManager::class.java)

        val totals = HashMap<String, Long>()
        val openSince = HashMap<String, Long>()
        val openActivities = HashMap<String, MutableSet<String>>()
        val seen = HashSet<String>()
        var rawEvents = 0
        val events = usm.queryEvents(start, end)
        val event = UsageEvents.Event()
        while (events != null && events.hasNextEvent()) {
            events.getNextEvent(event)
            rawEvents++
            val pkg = event.packageName ?: continue
            if (pkg !in packages) continue
            val ts = event.timeStamp
            val activities = openActivities.getOrPut(pkg) { HashSet() }
            when (event.eventType) {
                UsageEvents.Event.ACTIVITY_RESUMED -> {
                    if (activities.isEmpty()) openSince[pkg] = ts
                    activities.add(event.className ?: "")
                }
                UsageEvents.Event.ACTIVITY_PAUSED, UsageEvents.Event.ACTIVITY_STOPPED -> {
                    val wasOpen = activities.remove(event.className ?: "")
                    if (!wasOpen && pkg !in seen && event.eventType == UsageEvents.Event.ACTIVITY_PAUSED) {
                        // Already in the foreground at midnight.
                        totals[pkg] = (totals[pkg] ?: 0) + (ts - start)
                    } else if (wasOpen && activities.isEmpty()) {
                        totals[pkg] = (totals[pkg] ?: 0) + (ts - (openSince.remove(pkg) ?: ts))
                    }
                }
            }
            seen.add(pkg)
        }
        for ((pkg, since) in openSince) {
            if (openActivities[pkg]?.isNotEmpty() == true) {
                totals[pkg] = (totals[pkg] ?: 0) + (end - since)
            }
        }

        val stats = usm.queryAndAggregateUsageStats(start, end)
        val fg = HashMap<String, Long>()
        val visible = HashMap<String, Long>()
        for (pkg in packages) {
            val s = stats[pkg] ?: continue
            fg[pkg] = s.totalTimeInForeground
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) visible[pkg] = s.totalTimeVisible
        }
        val elapsed = (System.nanoTime() - t0) / 1_000_000
        return Usage(totals, fg, visible, rawEvents, stats.size, elapsed)
    }

    fun log(message: String) {
        Log.i(TAG, message)
    }
}
