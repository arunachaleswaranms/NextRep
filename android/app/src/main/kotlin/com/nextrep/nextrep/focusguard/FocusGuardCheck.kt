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
    /**
     * The notification couldn't be prepared (no notification service, the
     * channel or the notification couldn't be built). Android never saw it,
     * so nothing was claimed; the next check tries again.
     */
    NUDGE_NOT_READY,
    NUDGED,
    /**
     * `notify` threw after the day was claimed. Android may still have shown
     * the notification, so the claim is kept: no other nudge that day.
     */
    POST_UNCONFIRMED,
}

/**
 * A nudge ready to post. Everything that can fail before Android sees the
 * notification happened while preparing it; [post] only hands it to the
 * system, so a failure there can't prove it wasn't shown.
 */
fun interface PreparedNudge {
    fun post()
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

    /**
     * Builds the day's nudge without showing it. Throws if it can't be
     * prepared; Android has then not seen it.
     */
    fun prepareNudge(budgetMinutes: Int): PreparedNudge
}

/**
 * One Focus Guard background check (docs/PHASE_11C.md, "Worker").
 *
 * Exits as early as possible, re-checks Usage Access around the query (an
 * empty answer without access means nothing), and nudges at most once per
 * local day:
 *
 * 1. the notification is prepared first, so a failure that proves it was
 *    never shown happens before anything is claimed;
 * 2. the day is claimed in the database, atomically ([FocusGuardStore.claim]);
 * 3. only the check whose claim succeeded hands the notification to Android.
 *
 * A claim is never given back. If `notify` throws, Android may have shown the
 * notification anyway, so the day stays claimed; a crash between claim and
 * post also loses that day's nudge. At most once wins over at least once, and
 * no check, current or stale, can undo another's claim. Nothing about usage
 * is stored.
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
        if (FocusGuardStore.alreadyNudged(config.lastNudgedOn, today)) {
            return CheckOutcome.ALREADY_NUDGED
        }

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

        val nudge = try {
            platform.prepareNudge(config.dailyBudgetMinutes)
        } catch (e: Exception) {
            return CheckOutcome.NUDGE_NOT_READY
        }

        if (!store.claim(todayText, config.dailyBudgetMinutes, packages)) {
            return CheckOutcome.CLAIM_LOST
        }
        return try {
            nudge.post()
            CheckOutcome.NUDGED
        } catch (e: Exception) {
            // Ambiguous: the claim stays, so this day can't nudge again.
            CheckOutcome.POST_UNCONFIRMED
        }
    }
}
