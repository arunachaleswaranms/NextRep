package com.nextrep.nextrep.focusguard

import com.nextrep.nextrep.focusguard.UsageEventsCalculator.ACTIVITY_PAUSED
import com.nextrep.nextrep.focusguard.UsageEventsCalculator.ACTIVITY_RESUMED
import com.nextrep.nextrep.focusguard.UsageEventsCalculator.ACTIVITY_STOPPED
import com.nextrep.nextrep.focusguard.UsageEventsCalculator.DEVICE_SHUTDOWN
import com.nextrep.nextrep.focusguard.UsageEventsCalculator.DEVICE_STARTUP
import com.nextrep.nextrep.focusguard.UsageEventsCalculator.SCREEN_NON_INTERACTIVE
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/** Synthetic event streams only: org.example.* packages, minute timestamps. */
class UsageEventsCalculatorTest {
    private val min = 60_000L
    private val midnight = 1_000 * min
    private val queryStart = midnight - 360 * min
    private val a = "org.example.alpha"
    private val b = "org.example.beta"
    private val other = "org.example.other"

    private fun ev(pkg: String?, type: Int, atMinute: Long, cls: String = "Main") =
        UsageEvent(pkg, if (pkg == null) null else "$pkg.$cls", type, midnight + atMinute * min)

    private fun device(type: Int, atMinute: Long) = UsageEvent("android", null, type, midnight + atMinute * min)

    private fun run(
        vararg events: UsageEvent,
        packages: Set<String> = setOf(a, b),
        nowMinute: Long = 600,
    ): Map<String, Long> = UsageEventsCalculator.foregroundMillis(
        events.iterator(),
        packages,
        queryStart,
        midnight,
        midnight + nowMinute * min,
    ).mapValues { it.value / min }

    @Test
    fun noEventsMeansNoUsage() = assertEquals(emptyMap<String, Long>(), run())

    @Test
    fun resumedThenPausedCountsTheSession() =
        assertEquals(mapOf(a to 20L), run(ev(a, ACTIVITY_RESUMED, 60), ev(a, ACTIVITY_PAUSED, 80)))

    @Test
    fun stoppedClosesASessionToo() =
        assertEquals(mapOf(a to 5L), run(ev(a, ACTIVITY_RESUMED, 60), ev(a, ACTIVITY_STOPPED, 65)))

    @Test
    fun sessionsAddUp() = assertEquals(
        mapOf(a to 30L),
        run(
            ev(a, ACTIVITY_RESUMED, 10), ev(a, ACTIVITY_PAUSED, 20),
            ev(a, ACTIVITY_RESUMED, 100), ev(a, ACTIVITY_PAUSED, 120),
        ),
    )

    @Test
    fun aSessionStillOpenCountsUpToNow() =
        assertEquals(mapOf(a to 15L), run(ev(a, ACTIVITY_RESUMED, 585), nowMinute = 600))

    @Test
    fun aSessionAcrossMidnightCountsFromMidnight() =
        assertEquals(mapOf(a to 30L), run(ev(a, ACTIVITY_RESUMED, -45), ev(a, ACTIVITY_PAUSED, 30)))

    @Test
    fun yesterdaysClosedSessionsDoNotCount() =
        assertEquals(emptyMap<String, Long>(), run(ev(a, ACTIVITY_RESUMED, -90), ev(a, ACTIVITY_PAUSED, -10)))

    @Test
    fun alreadyInTheForegroundWhenTheStreamBegins() =
        // The first event is an unmatched pause: in the foreground since
        // before the stream, so counted from midnight.
        assertEquals(mapOf(a to 40L), run(ev(a, ACTIVITY_PAUSED, 40)))

    @Test
    fun otherEventTypesDoNotHideAnAppAlreadyInTheForeground() =
        // A notification or standby-bucket event first must not make the
        // later unmatched pause look like a duplicate.
        assertEquals(
            mapOf(a to 40L),
            run(ev(a, 12, -100), ev(a, 11, 10), ev(a, ACTIVITY_PAUSED, 40)),
        )

    @Test
    fun anAppAlreadyInTheForegroundCountsOnlySinceTheLastScreenOff() =
        // The screen went off at 0:10; the pause at 0:40 without a resume
        // can't mean foreground before 0:10.
        assertEquals(
            mapOf(a to 30L),
            run(device(SCREEN_NON_INTERACTIVE, 10), ev(a, ACTIVITY_PAUSED, 40)),
        )

    @Test
    fun anUnmatchedStopFirstIsNotForeground() =
        // Paused before the stream began, stopped later: not foreground.
        assertEquals(emptyMap<String, Long>(), run(ev(a, ACTIVITY_STOPPED, 40)))

    @Test
    fun aLaterDuplicatePauseIsIgnored() = assertEquals(
        mapOf(a to 10L),
        run(ev(a, ACTIVITY_RESUMED, 10), ev(a, ACTIVITY_PAUSED, 20), ev(a, ACTIVITY_PAUSED, 50)),
    )

    @Test
    fun overlappingActivitiesOfOnePackageCountOnce() = assertEquals(
        // Two activities of the same app resumed together (split screen):
        // the session runs from the first resume to the last pause.
        mapOf(a to 30L),
        run(
            ev(a, ACTIVITY_RESUMED, 10, "One"),
            ev(a, ACTIVITY_RESUMED, 15, "Two"),
            ev(a, ACTIVITY_PAUSED, 25, "One"),
            ev(a, ACTIVITY_PAUSED, 40, "Two"),
        ),
    )

    @Test
    fun aRepeatedResumeOfTheSameActivityDoesNotRestartTheSession() = assertEquals(
        mapOf(a to 20L),
        run(ev(a, ACTIVITY_RESUMED, 10), ev(a, ACTIVITY_RESUMED, 15), ev(a, ACTIVITY_PAUSED, 30)),
    )

    @Test
    fun splitScreenAppsEachCountTheirOwnTime() = assertEquals(
        mapOf(a to 30L, b to 20L),
        run(
            ev(a, ACTIVITY_RESUMED, 10),
            ev(b, ACTIVITY_RESUMED, 20),
            ev(b, ACTIVITY_PAUSED, 40),
            ev(a, ACTIVITY_PAUSED, 40),
        ),
    )

    @Test
    fun onlySelectedPackagesCount() = assertEquals(
        mapOf(a to 10L),
        run(
            ev(a, ACTIVITY_RESUMED, 10), ev(a, ACTIVITY_PAUSED, 20),
            ev(other, ACTIVITY_RESUMED, 20), ev(other, ACTIVITY_PAUSED, 300),
        ),
    )

    @Test
    fun screenOffEndsEverySession() = assertEquals(
        mapOf(a to 20L, b to 15L),
        run(
            ev(a, ACTIVITY_RESUMED, 10),
            ev(b, ACTIVITY_RESUMED, 15),
            device(SCREEN_NON_INTERACTIVE, 30),
            // A late pause after the screen went off adds nothing.
            ev(a, ACTIVITY_PAUSED, 200),
        ),
    )

    @Test
    fun aMissingPauseIsBoundedByTheNextScreenOff() = assertEquals(
        // Yesterday's session without a pause (e.g. a crash) ends at the
        // screen-off, so only 0:00–0:05 counts.
        mapOf(a to 5L),
        run(ev(a, ACTIVITY_RESUMED, -30), device(SCREEN_NON_INTERACTIVE, 5)),
    )

    @Test
    fun shutdownEndsSessionsAndStartupDropsDanglingOnes() {
        assertEquals(mapOf(a to 20L), run(ev(a, ACTIVITY_RESUMED, 10), device(DEVICE_SHUTDOWN, 30)))
        assertEquals(
            emptyMap<String, Long>(),
            run(ev(a, ACTIVITY_RESUMED, 10), device(DEVICE_STARTUP, 300)),
        )
    }

    @Test
    fun eventsAfterNowAreIgnored() =
        assertEquals(mapOf(a to 10L), run(ev(a, ACTIVITY_RESUMED, 590), ev(a, ACTIVITY_PAUSED, 700), nowMinute = 600))

    @Test
    fun noPackageExceedsTheWindow() {
        val result = run(ev(a, ACTIVITY_RESUMED, -300), nowMinute = 30)
        assertEquals(mapOf(a to 30L), result)
    }

    @Test
    fun eventsWithoutAPackageAreSkipped() =
        assertEquals(emptyMap<String, Long>(), run(UsageEvent(null, null, ACTIVITY_RESUMED, midnight)))

    @Test
    fun anEmptyWindowCountsNothing() {
        val result = UsageEventsCalculator.foregroundMillis(
            listOf(UsageEvent(a, "x", ACTIVITY_RESUMED, midnight - min)).iterator(),
            setOf(a),
            queryStart,
            midnight,
            midnight,
        )
        assertTrue(result.values.all { it == 0L })
    }
}
