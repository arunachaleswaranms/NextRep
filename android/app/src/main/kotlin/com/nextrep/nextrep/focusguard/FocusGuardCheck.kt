package com.nextrep.nextrep.focusguard

import java.time.Instant
import java.time.ZoneId

/** What one background check did. Never carries apps or amounts. */
enum class CheckOutcome {
    /** No database yet, or not the schema this code reads. */
    STORE_UNAVAILABLE,
    /** The stored values break Drift's rules; nothing was decided. */
    CONFIG_UNREADABLE,
    DISABLED,
    NO_APPS,
    ALREADY_NUDGED,
    NO_USAGE_ACCESS,
    USAGE_FAILED,
    BELOW_BUDGET,
    NOTIFICATIONS_OFF,
    /** Local midnight passed during the check; the next one decides. */
    DAY_CHANGED,
    /** The claim matched nothing: another check nudged, or settings changed. */
    CLAIM_LOST,
    NUDGED,
    /** Posting threw; the claim was given back if possible. */
    POST_FAILED,
}

/** The device facilities a check uses; faked in JVM tests. */
interface CheckPlatform {
    fun nowMillis(): Long

    fun zone(): ZoneId

    /** Re-read on every call: the user can revoke it at any time. */
    fun usageAccessGranted(): Boolean

    /** Throws if the platform query fails. */
    fun foregroundMillis(packages: Set<String>, windowStart: Long, windowEnd: Long): Map<String, Long>

    /** Notifications on for NextRep and the Focus Guard channel not blocked. */
    fun nudgesAllowed(): Boolean

    /** Throws if the notification could not be posted. */
    fun postNudge(budgetMinutes: Int)
}

/**
 * One Focus Guard background check (docs/PHASE_11C.md, "Worker").
 *
 * Exits as early as possible, re-checks Usage Access around the query (an
 * empty answer without access means nothing), and nudges at most once per
 * local day: the day is claimed in the database first, atomically, and only
 * then is the notification posted. A crash between the two loses that day's
 * nudge rather than ever sending a second one. Nothing about usage is stored.
 */
class FocusGuardCheck(private val store: FocusGuardStore, private val platform: CheckPlatform) {
    fun run(): CheckOutcome {
        val config = try {
            store.load() ?: return CheckOutcome.DISABLED
        } catch (e: UnreadableConfigException) {
            return CheckOutcome.CONFIG_UNREADABLE
        }
        if (!config.enabled) return CheckOutcome.DISABLED
        if (config.packages.isEmpty()) return CheckOutcome.NO_APPS

        val zone = platform.zone()
        val now = platform.nowMillis()
        val today = Instant.ofEpochMilli(now).atZone(zone).toLocalDate()
        val todayText = today.toString()
        if (config.lastNudgedOn == todayText) return CheckOutcome.ALREADY_NUDGED

        if (!platform.usageAccessGranted()) return CheckOutcome.NO_USAGE_ACCESS
        val packages = config.packages.toSet()
        val windowStart = today.atStartOfDay(zone).toInstant().toEpochMilli()
        val perPackage = try {
            platform.foregroundMillis(packages, windowStart, now)
        } catch (e: Exception) {
            return CheckOutcome.USAGE_FAILED
        }
        // Revoked while the query ran: its (empty) answer means nothing.
        if (!platform.usageAccessGranted()) return CheckOutcome.NO_USAGE_ACCESS

        val window = now - windowStart
        val total = perPackage
            .filterKeys { it in packages }
            .values
            .sumOf { it.coerceIn(0L, window) }
            .coerceAtMost(window)
        val budget = config.dailyBudgetMinutes * 60_000L
        if (total < budget) return CheckOutcome.BELOW_BUDGET

        // Denied notifications don't use up the day's nudge.
        if (!platform.nudgesAllowed()) return CheckOutcome.NOTIFICATIONS_OFF
        val stillToday = Instant.ofEpochMilli(platform.nowMillis()).atZone(zone).toLocalDate()
        if (stillToday != today) return CheckOutcome.DAY_CHANGED

        if (!store.claim(todayText, config.dailyBudgetMinutes, packages)) {
            return CheckOutcome.CLAIM_LOST
        }
        return try {
            platform.postNudge(config.dailyBudgetMinutes)
            CheckOutcome.NUDGED
        } catch (e: Exception) {
            try {
                store.release(todayText, config.lastNudgedOn)
            } catch (ignored: Exception) {
                // The day stays claimed: at most one nudge, never two.
            }
            CheckOutcome.POST_FAILED
        }
    }
}
