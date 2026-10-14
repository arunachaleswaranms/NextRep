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
        var postFails = false
        val posted = AtomicInteger()
        val queries = AtomicInteger()
        var lastWindow: Pair<Long, Long>? = null

        override fun nowMillis() = now
        override fun zone(): ZoneId = this@FocusGuardCheckTest.zone
        override fun usageAccessGranted() = access

        override fun foregroundMillis(packages: Set<String>, windowStart: Long, windowEnd: Long): Map<String, Long> {
            queries.incrementAndGet()
            lastWindow = windowStart to windowEnd
            accessAfterQuery?.let { access = it }
            if (queryFails) throw IllegalStateException("query failed")
            return usage
        }

        override fun nudgesAllowed() = nudges

        override fun postNudge(budgetMinutes: Int) {
            if (postFails) throw IllegalStateException("post failed")
            posted.incrementAndGet()
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
    fun aFailedPostGivesTheDayBack() {
        db.save(enabled = true, budget = 60, packages = apps, lastNudgedOnForNewRow = "2026-10-10")
        usage(90)
        platform.postFails = true
        assertEquals(CheckOutcome.POST_FAILED, check())
        assertEquals("2026-10-10", db.lastNudgedOn())
        platform.postFails = false
        assertEquals(CheckOutcome.NUDGED, check())
        assertEquals(1, platform.posted.get())
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
