package com.nextrep.nextrep.focusguard

import android.Manifest
import android.app.AppOpsManager
import android.app.usage.UsageEvents
import android.app.usage.UsageStatsManager
import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.content.pm.LauncherApps
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Process
import android.provider.Settings

/**
 * Android's app-usage facilities, as qualified in Phase 11A: Usage Access
 * through AppOpsManager, apps from LauncherApps (with the manifest's narrow
 * MAIN/LAUNCHER `<queries>`, never QUERY_ALL_PACKAGES), and foreground time
 * from UsageStatsManager.queryEvents. Shared by the UI's method channel and
 * the background check. Reads only; nothing is stored, and nothing about
 * apps or amounts is logged.
 */
object FocusGuardUsage {
    /**
     * Events from this long before local midnight are read too, so a session
     * that began before midnight counts from midnight. A screen-off ends any
     * session, so a longer look back changes nothing in practice.
     */
    const val LOOKBACK_MS = 6 * 60 * 60 * 1000L

    /** Never prompts. Re-read before every use. */
    fun usageAccessGranted(context: Context): Boolean {
        val appOps = context.getSystemService(AppOpsManager::class.java) ?: return false
        val mode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            appOps.unsafeCheckOpNoThrow(
                AppOpsManager.OPSTR_GET_USAGE_STATS,
                Process.myUid(),
                context.packageName,
            )
        } else {
            @Suppress("DEPRECATION")
            appOps.checkOpNoThrow(
                AppOpsManager.OPSTR_GET_USAGE_STATS,
                Process.myUid(),
                context.packageName,
            )
        }
        return if (mode == AppOpsManager.MODE_DEFAULT) {
            context.checkCallingOrSelfPermission(Manifest.permission.PACKAGE_USAGE_STATS) ==
                PackageManager.PERMISSION_GRANTED
        } else {
            mode == AppOpsManager.MODE_ALLOWED
        }
    }

    /**
     * Opens NextRep's own Usage Access page (Android 10+ honours the
     * `package:` data), falling back to the general list. Called only from a
     * user's tap. Returns whether a settings page opened.
     */
    fun openUsageAccessSettings(context: Context): Boolean {
        val own = Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS)
            .setData(Uri.parse("package:${context.packageName}"))
        val general = Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS)
        for (intent in listOf(own, general)) {
            if (context !is android.app.Activity) intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            try {
                context.startActivity(intent)
                return true
            } catch (e: ActivityNotFoundException) {
                // Try the next one.
            } catch (e: SecurityException) {
                // Try the next one.
            }
        }
        return false
    }

    /**
     * Apps with a launcher entry for the current user, without NextRep
     * itself. Labels are read live and never stored.
     */
    fun launchableApps(context: Context): List<Map<String, String>> {
        val launcher = context.getSystemService(LauncherApps::class.java) ?: return emptyList()
        return launcher.getActivityList(null, Process.myUserHandle())
            .filter { it.applicationInfo.packageName != context.packageName }
            .map {
                mapOf(
                    "packageName" to it.applicationInfo.packageName,
                    "label" to (it.label?.toString() ?: ""),
                )
            }
    }

    /**
     * Foreground time of [packages] between [windowStart] and [windowEnd]
     * (epoch milliseconds), by [UsageEventsCalculator]. Without Usage Access
     * Android returns no events rather than an error, so callers check
     * access before and after. Throws if the query fails.
     */
    fun foregroundMillis(
        context: Context,
        packages: Set<String>,
        windowStart: Long,
        windowEnd: Long,
    ): Map<String, Long> {
        if (packages.isEmpty() || windowEnd <= windowStart) return emptyMap()
        val manager = context.getSystemService(UsageStatsManager::class.java)
            ?: throw IllegalStateException("UsageStatsManager unavailable")
        val queryStart = windowStart - LOOKBACK_MS
        val events = manager.queryEvents(queryStart, windowEnd)
            ?: throw IllegalStateException("No usage events")
        return UsageEventsCalculator.foregroundMillis(
            events.asSequence(packages).iterator(),
            packages,
            queryStart,
            windowStart,
            windowEnd,
        )
    }

    /**
     * The events the calculation reads: the selected packages' activity
     * events and the device-wide screen-off / shutdown / startup events.
     */
    private fun UsageEvents.asSequence(packages: Set<String>): Sequence<UsageEvent> {
        val event = UsageEvents.Event()
        return generateSequence {
            if (!hasNextEvent()) return@generateSequence null
            getNextEvent(event)
            UsageEvent(event.packageName, event.className, event.eventType, event.timeStamp)
        }.filter {
            when (it.type) {
                UsageEventsCalculator.SCREEN_NON_INTERACTIVE,
                UsageEventsCalculator.DEVICE_SHUTDOWN,
                UsageEventsCalculator.DEVICE_STARTUP,
                -> true
                else -> it.packageName in packages
            }
        }
    }
}
