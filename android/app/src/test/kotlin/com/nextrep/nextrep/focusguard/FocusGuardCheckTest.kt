package com.nextrep.nextrep.focusguard

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.LocalDateTime
import java.time.ZoneId
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger

/**
 * One background check, end to end over a real SQLite file with Drift's
 * tables: the decisions, and at most one nudge per local day.
 */
class FocusGuardCheckTest {
    private val zone = ZoneId.of("Europe/Berlin")
    private val apps = listOf("org.example.alpha", "org.example.beta")
    private val db = DriftFixture.create()
    private val min = 60_000L

    private inner class FakePlatform : CheckPlatform {
        var now = at(2026, 10, 14, 18, 0)
        var access = true
        var accessAfterQuery: Boolean? = null
        var usage: Map<String, Long> = emptyMap()
        var queryFails = false
        var nudges = true

        /** Preparing fails: Android never sees the notification. */
        var prepareFails = false

        /** `notify` throws without showing anything (indistinguishable). */
        var notifyThrows = false

        /** `notify` shows the notification, then throws anyway. */
        var notifyShowsThenThrows = false
        var duringQuery: (() -> Unit)? = null

        /** Notifications Android actually showed. */
        val posted = AtomicInteger()
        val postAttempts = AtomicInteger()
        val queries = AtomicInteger()
        var lastWindow: Pair<Long, Long>? = null

        override fun nowMillis() = now
        override fun zone(): ZoneId = this@FocusGuardCheckTest.zone
        override fun usageAccessGranted() = access

        override fun foregroundMillis(packages: Set<String>, windowStart: Long, windowEnd: Long): Map<String, Long> {
            queries.incrementAndGet()
            lastWindow = windowStart to windowEnd
            accessAfterQuery?.let { access = it }
            duringQuery?.invoke()
            if (queryFails) throw IllegalStateException("query failed")
            return usage
        }

        override fun nudgesAllowed() = nudges

        override fun prepareNudge(budgetMinutes: Int): PreparedNudge {
            if (prepareFails) throw IllegalStateException("no notification service")
            return PreparedNudge {
                postAttempts.incrementAndGet()
                if (notifyThrows) throw IllegalStateException("notify failed")
                posted.incrementAndGet()
                if (notifyShowsThenThrows) throw RuntimeException("binder died after posting")
            }
        }
    }

    private fun at(y: Int, m: Int, d: Int, h: Int, mi: Int): Long =
        LocalDateTime.of(y, m, d, h, mi).atZone(zone).toInstant().toEpochMilli()

    private val platform = FakePlatform()

    private fun check(): CheckOutcome = db.withStore { FocusGuardCheck(it, platform).run() }

    private fun usage(alpha: Long, beta: Long = 0) {
        platform.usage = mapOf(apps[0] to alpha * min, apps[1] to beta * min)
    }

    private fun on(budget: Int = 60) = db.save(enabled = true, budget = budget, packages = apps)

    @Test
    fun nothingConfiguredOrOff() {
        assertEquals(CheckOutcome.DISABLED, check())
        db.save(enabled = false, budget = 60, packages = apps)
        usage(500)
        assertEquals(CheckOutcome.DISABLED, check())
        assertEquals(0, platform.queries.get())
    }

    @Test
    fun noAppsSelected() {
        db.save(enabled = true, budget = 60, packages = emptyList())
        assertEquals(CheckOutcome.NO_APPS, check())
    }

    @Test
    fun unreadableConfigurationDecidesNothing() {
        on()
        db.exec("UPDATE focus_guard_preferences SET last_nudged_on = 'soon'")
        usage(500)
        assertEquals(CheckOutcome.CONFIG_UNREADABLE, check())
        assertEquals(0, platform.posted.get())
    }

    @Test
    fun withoutUsageAccessNothingIsMeasured() {
        on()
        platform.access = false
        assertEquals(CheckOutcome.NO_USAGE_ACCESS, check())
        assertEquals(0, platform.queries.get())
    }

    @Test
    fun revokedDuringTheQueryMeansUnavailableNotZero() {
        on()
        usage(500)
        platform.accessAfterQuery = false
        assertEquals(CheckOutcome.NO_USAGE_ACCESS, check())
        assertEquals(0, platform.posted.get())
    }

    @Test
    fun aFailedQueryDecidesNothing() {
        on()
        platform.queryFails = true
        assertEquals(CheckOutcome.USAGE_FAILED, check())
    }

    @Test
    fun measuresFromLocalMidnightToNow() {
        on()
        check()
        assertEquals(at(2026, 10, 14, 0, 0) to platform.now, platform.lastWindow)
    }

    @Test
    fun belowTheCombinedBudgetNoNudge() {
        on()
        usage(20, 39) // 59 minutes of 60
        platform.usage = platform.usage + ("org.example.unselected" to 500 * min)
        assertEquals(CheckOutcome.BELOW_BUDGET, check())
        assertEquals(0, platform.posted.get())
    }

    @Test
    fun aMillisecondShortIsStillBelow() {
        on()
        platform.usage = mapOf(apps[0] to 60 * min - 1)
        assertEquals(CheckOutcome.BELOW_BUDGET, check())
    }

    @Test
    fun exactlyTheBudgetNudgesOnce() {
        on()
        usage(25, 35)
        assertEquals(CheckOutcome.NUDGED, check())
        assertEquals(1, platform.posted.get())
        assertEquals("2026-10-14", db.lastNudgedOn())
    }

    @Test
    fun overTheBudgetNudgesOnceAndNeverAgainThatDay() {
        on()
        usage(61)
        assertEquals(CheckOutcome.NUDGED, check())
        for (minutes in listOf(75L, 120L, 600L)) {
            usage(minutes)
            platform.now += 15 * min
            assertEquals(CheckOutcome.ALREADY_NUDGED, check())
        }
        assertEquals(1, platform.posted.get())
    }

    @Test
    fun theNextLocalDayIsEligibleAgain() {
        on()
        usage(61)
        check()
        platform.now = at(2026, 10, 15, 9, 0)
        usage(10)
        assertEquals(CheckOutcome.BELOW_BUDGET, check())
        usage(61)
        assertEquals(CheckOutcome.NUDGED, check())
        assertEquals(2, platform.posted.get())
        assertEquals("2026-10-15", db.lastNudgedOn())
    }

    @Test
    fun deniedNotificationsDoNotUseUpTheDay() {
        on()
        usage(90)
        platform.nudges = false
        assertEquals(CheckOutcome.NOTIFICATIONS_OFF, check())
        assertEquals(null, db.lastNudgedOn())
        platform.nudges = true
        assertEquals(CheckOutcome.NUDGED, check())
        assertEquals(1, platform.posted.get())
    }

    @Test
    fun aFailureBeforeDeliveryClaimsNothingAndTheNextCheckNudges() {
        on()
        usage(90)
        platform.prepareFails = true
        assertEquals(CheckOutcome.NUDGE_NOT_READY, check())
        assertEquals(null, db.lastNudgedOn())
        assertEquals(0, platform.postAttempts.get())
        platform.prepareFails = false
        assertEquals(CheckOutcome.NUDGED, check())
        assertEquals(1, platform.posted.get())
    }

    @Test
    fun anAmbiguousFailureAfterAndroidAcceptedTheNotificationKeepsTheDay() {
        on()
        usage(90)
        platform.notifyShowsThenThrows = true
        assertEquals(CheckOutcome.POST_UNCONFIRMED, check())
        assertEquals("2026-10-14", db.lastNudgedOn())
        assertEquals(1, platform.posted.get())
    }

    @Test
    fun aThrowingNotifyIsTreatedAsShown() {
        // Nothing distinguishes "not shown" from "shown, then failed": the
        // day stays claimed either way.
        on()
        usage(90)
        platform.notifyThrows = true
        assertEquals(CheckOutcome.POST_UNCONFIRMED, check())
        assertEquals("2026-10-14", db.lastNudgedOn())
        platform.notifyThrows = false
        platform.now += 15 * min
        assertEquals(CheckOutcome.ALREADY_NUDGED, check())
        assertEquals(1, platform.postAttempts.get())
        // The next local day is eligible again.
        platform.now = at(2026, 10, 15, 18, 0)
        assertEquals(CheckOutcome.NUDGED, check())
    }

    @Test
    fun repeatedChecksAfterAnAmbiguousFailureNeverNudgeAgain() {
        on()
        usage(90)
        platform.notifyShowsThenThrows = true
        check()
        platform.notifyShowsThenThrows = false
        repeat(5) {
            platform.now += 15 * min
            assertEquals(CheckOutcome.ALREADY_NUDGED, check())
        }
        // A new process with nothing in memory.
        val fresh = FakePlatform().apply { now = platform.now; usage = platform.usage }
        assertEquals(CheckOutcome.ALREADY_NUDGED, db.withStore { FocusGuardCheck(it, fresh).run() })
        assertEquals(1, platform.posted.get() + fresh.posted.get())
        assertEquals(1, platform.postAttempts.get() + fresh.postAttempts.get())
    }

    @Test
    fun concurrentChecksWhoseNotifyThrowsStillShowAtMostOne() {
        on()
        usage(90)
        platform.notifyShowsThenThrows = true
        val threads = 12
        val pool = Executors.newFixedThreadPool(threads)
        val start = CountDownLatch(1)
        val outcomes = java.util.concurrent.ConcurrentLinkedQueue<CheckOutcome>()
        repeat(threads) {
            pool.execute {
                start.await()
                outcomes.add(db.withStore { FocusGuardCheck(it, platform).run() })
            }
        }
        start.countDown()
        pool.shutdown()
        assertTrue(pool.awaitTermination(30, TimeUnit.SECONDS))
        assertEquals(1, platform.postAttempts.get())
        assertEquals(1, outcomes.count { it == CheckOutcome.POST_UNCONFIRMED })
        assertEquals("2026-10-14", db.lastNudgedOn())
    }

    @Test
    fun aCheckMadeStaleByARestoreClaimsNothing() {
        on()
        usage(90)
        // The restore lands while the check is measuring.
        platform.duringQuery = { db.restore(budget = 60, packages = apps) }
        assertEquals(CheckOutcome.CLAIM_LOST, check())
        assertEquals(0, platform.postAttempts.get())
        assertEquals(null, db.lastNudgedOn())
    }

    @Test
    fun aCheckMadeStaleByAReconfigurationClaimsNothing() {
        on(budget = 60)
        usage(90)
        platform.duringQuery = { db.save(enabled = true, budget = 120, packages = apps) }
        assertEquals(CheckOutcome.CLAIM_LOST, check())
        on(budget = 60)
        platform.duringQuery = { db.save(enabled = true, budget = 60, packages = listOf(apps[0])) }
        assertEquals(CheckOutcome.CLAIM_LOST, check())
        assertEquals(0, platform.postAttempts.get())
        assertEquals(null, db.lastNudgedOn())
    }

    @Test
    fun aStaleCheckCannotUndoANewerClaim() {
        on()
        usage(90)
        // While this check measures, the user restores, turns Focus Guard
        // back on, and another check nudges for today.
        val other = FakePlatform().apply { now = platform.now; usage = platform.usage }
        platform.duringQuery = {
            db.restore(budget = 60, packages = apps)
            db.save(enabled = true, budget = 60, packages = apps)
            assertEquals(CheckOutcome.NUDGED, db.withStore { FocusGuardCheck(it, other).run() })
        }
        assertEquals(CheckOutcome.CLAIM_LOST, check())
        assertEquals("2026-10-14", db.lastNudgedOn())
        assertEquals(0, platform.postAttempts.get())
        assertEquals(1, other.posted.get())
    }

    @Test
    fun aCheckThatMeasuredYesterdayCannotReplaceTodaysClaim() {
        on()
        usage(90)
        // Measured just before midnight; the store meanwhile holds today's
        // nudge (made by another check after midnight).
        platform.now = at(2026, 10, 14, 23, 59)
        platform.duringQuery = { db.exec("UPDATE focus_guard_preferences SET last_nudged_on = '2026-10-15'") }
        assertEquals(CheckOutcome.CLAIM_LOST, check())
        assertEquals("2026-10-15", db.lastNudgedOn())
        assertEquals(0, platform.postAttempts.get())
    }

    @Test
    fun aNudgeRecordedForTomorrowCountsAsToday() {
        // Recorded before a westward time-zone change: no second nudge.
        db.save(enabled = true, budget = 60, packages = apps, lastNudgedOnForNewRow = "2026-10-15")
        usage(90)
        assertEquals(CheckOutcome.ALREADY_NUDGED, check())
        assertEquals(0, platform.queries.get())
    }

    @Test
    fun aDateFarAheadFromAWrongClockDoesNotBlockFocusGuard() {
        db.save(enabled = true, budget = 60, packages = apps, lastNudgedOnForNewRow = "2030-01-01")
        usage(90)
        assertEquals(CheckOutcome.NUDGED, check())
        assertEquals("2026-10-14", db.lastNudgedOn())
    }

    @Test
    fun editingTheBudgetOrTogglingAfterANudgeDoesNotNudgeAgain() {
        on(budget = 60)
        usage(61)
        assertEquals(CheckOutcome.NUDGED, check())
        on(budget = 30) // a stale UI save: keeps the nudge date
        assertEquals(CheckOutcome.ALREADY_NUDGED, check())
        db.save(enabled = false, budget = 30, packages = apps)
        assertEquals(CheckOutcome.DISABLED, check())
        on(budget = 30)
        assertEquals(CheckOutcome.ALREADY_NUDGED, check())
        assertEquals(1, platform.posted.get())
    }

    @Test
    fun aRestoreStopsTheCheck() {
        on()
        usage(500)
        db.restore(budget = 60, packages = apps)
        assertEquals(CheckOutcome.DISABLED, check())
        assertEquals(0, platform.posted.get())
    }

    @Test
    fun aRestartedCheckOnTheSameDayDoesNotNudgeAgain() {
        on()
        usage(61)
        check()
        // A new process: nothing in memory, only the stored date.
        val fresh = FakePlatform().apply { now = platform.now + 60 * min; usage = platform.usage }
        assertEquals(CheckOutcome.ALREADY_NUDGED, db.withStore { FocusGuardCheck(it, fresh).run() })
        assertEquals(0, fresh.posted.get())
    }

    @Test
    fun concurrentChecksNudgeAtMostOnce() {
        on()
        usage(90)
        val threads = 12
        val pool = Executors.newFixedThreadPool(threads)
        val start = CountDownLatch(1)
        repeat(threads) {
            pool.execute {
                start.await()
                db.withStore { FocusGuardCheck(it, platform).run() }
            }
        }
        start.countDown()
        pool.shutdown()
        assertTrue(pool.awaitTermination(30, TimeUnit.SECONDS))
        assertEquals(1, platform.posted.get())
    }

    @Test
    fun totalsAreCappedAtTheWindow() {
        on(budget = 1440)
        platform.now = at(2026, 10, 14, 23, 0)
        // Two split-screen apps each reporting the whole day.
        usage(23 * 60, 23 * 60)
        assertEquals(CheckOutcome.BELOW_BUDGET, check())
    }

    @Test
    fun aDaylightSavingDayIsMeasuredFromItsOwnMidnight() {
        on()
        platform.now = at(2026, 10, 25, 12, 0) // the day Berlin leaves DST
        check()
        assertEquals(at(2026, 10, 25, 0, 0), platform.lastWindow!!.first)
        assertEquals(13 * 60 * min, platform.lastWindow!!.second - platform.lastWindow!!.first)
    }
}
