package com.nextrep.nextrep.focusguard

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger

/** The worker's SQL against a real SQLite file with Drift's v6 tables. */
class FocusGuardStoreTest {
    private val apps = listOf("org.example.alpha", "org.example.beta")
    private val db = DriftFixture.create()

    @Test
    fun readsTheSchemaVersion() = assertEquals(6L, db.withStore { it.schemaVersion() })

    @Test
    fun noRowMeansNotConfigured() = assertNull(db.withStore { it.load() })

    @Test
    fun readsDriftsRepresentationInOrder() {
        db.save(enabled = true, budget = 45, packages = apps.reversed(), lastNudgedOnForNewRow = "2026-10-05")
        assertEquals(
            FocusGuardConfig(true, 45, "2026-10-05", apps.reversed()),
            db.withStore { it.load() },
        )
    }

    @Test
    fun readsAConfigurationWithoutApps() {
        db.save(enabled = false, budget = 60, packages = emptyList())
        assertEquals(FocusGuardConfig(false, 60, null, emptyList()), db.withStore { it.load() })
    }

    @Test
    fun valuesDriftNeverWritesAreUnreadable() {
        db.save(enabled = true, budget = 60, packages = apps)
        db.exec("UPDATE focus_guard_preferences SET last_nudged_on = 'yesterday'")
        assertThrows(UnreadableConfigException::class.java) { db.withStore { it.load() } }
        db.exec("UPDATE focus_guard_preferences SET last_nudged_on = NULL")
        db.exec("UPDATE focus_guard_selected_apps SET package_name = 'not a package' WHERE sort_order = 0")
        assertThrows(UnreadableConfigException::class.java) { db.withStore { it.load() } }
    }

    @Test
    fun claimsADayOnce() {
        db.save(enabled = true, budget = 60, packages = apps)
        assertTrue(db.withStore { it.claim("2026-10-14", 60, apps.toSet()) })
        assertFalse(db.withStore { it.claim("2026-10-14", 60, apps.toSet()) })
        assertEquals("2026-10-14", db.lastNudgedOn())
        // The next local day is eligible again.
        assertTrue(db.withStore { it.claim("2026-10-15", 60, apps.toSet()) })
    }

    @Test
    fun aClaimChangesOnlyTheNudgeDate() {
        db.save(enabled = true, budget = 60, packages = apps, updatedAt = 1_700_000_000L)
        db.withStore { it.claim("2026-10-14", 60, apps.toSet()) }
        db.connect().use { c ->
            c.createStatement().executeQuery(
                "SELECT enabled, daily_budget_minutes, updated_at, " +
                    "(SELECT COUNT(*) FROM focus_guard_selected_apps) FROM focus_guard_preferences",
            ).use { rs ->
                rs.next()
                assertEquals(1, rs.getInt(1))
                assertEquals(60, rs.getInt(2))
                assertEquals(1_700_000_000L, rs.getLong(3))
                assertEquals(2, rs.getInt(4))
            }
        }
    }

    @Test
    fun noClaimWhileOffOrAfterARestore() {
        db.save(enabled = false, budget = 60, packages = apps)
        assertFalse(db.withStore { it.claim("2026-10-14", 60, apps.toSet()) })
        db.save(enabled = true, budget = 60, packages = apps)
        db.restore(budget = 60, packages = apps)
        assertFalse(db.withStore { it.claim("2026-10-14", 60, apps.toSet()) })
        assertNull(db.lastNudgedOn())
    }

    @Test
    fun noClaimWhenTheBudgetOrAppsChangedSinceTheMeasurement() {
        db.save(enabled = true, budget = 60, packages = apps)
        assertFalse(db.withStore { it.claim("2026-10-14", 30, apps.toSet()) })
        assertFalse(db.withStore { it.claim("2026-10-14", 60, setOf(apps[0])) })
        assertFalse(db.withStore { it.claim("2026-10-14", 60, apps.toSet() + "org.example.gamma") })
        assertFalse(db.withStore { it.claim("2026-10-14", 60, setOf(apps[0], "org.example.gamma")) })
        assertNull(db.lastNudgedOn())
        assertTrue(db.withStore { it.claim("2026-10-14", 60, apps.toSet()) })
    }

    @Test
    fun claimsOnlyMoveForward() {
        db.save(enabled = true, budget = 60, packages = apps, lastNudgedOnForNewRow = "2026-10-15")
        // An earlier day (a stale check) can't replace a later one.
        assertFalse(db.withStore { it.claim("2026-10-14", 60, apps.toSet()) })
        assertFalse(db.withStore { it.claim("2026-10-15", 60, apps.toSet()) })
        assertEquals("2026-10-15", db.lastNudgedOn())
        assertTrue(db.withStore { it.claim("2026-10-16", 60, apps.toSet()) })
        assertEquals("2026-10-16", db.lastNudgedOn())
    }

    @Test
    fun aDateMoreThanADayAheadIsReplaced() {
        // Written while the clock was wrong; a corrected clock still works.
        db.save(enabled = true, budget = 60, packages = apps, lastNudgedOnForNewRow = "2030-01-01")
        assertTrue(db.withStore { it.claim("2026-10-14", 60, apps.toSet()) })
        assertEquals("2026-10-14", db.lastNudgedOn())
    }

    @Test
    fun alreadyNudgedMatchesWhatClaimRefuses() {
        val today = java.time.LocalDate.of(2026, 10, 14)
        for ((stored, covered) in listOf(
            null to false,
            "2026-10-13" to false,
            "2026-10-14" to true,
            "2026-10-15" to true,
            "2026-10-16" to false,
        )) {
            assertEquals(stored, covered, FocusGuardStore.alreadyNudged(stored, today))
            val fixture = DriftFixture.create()
            fixture.save(enabled = true, budget = 60, packages = apps, lastNudgedOnForNewRow = stored)
            assertEquals(stored, !covered, fixture.withStore { it.claim("2026-10-14", 60, apps.toSet()) })
        }
    }

    @Test
    fun aForegroundSaveKeepsTheWorkersNudgeDate() {
        // The UI loaded its settings before the worker nudged, then saves a
        // budget change from that stale copy (lastNudgedOn null in memory).
        db.save(enabled = true, budget = 60, packages = apps)
        db.withStore { it.claim("2026-10-14", 60, apps.toSet()) }
        db.save(enabled = true, budget = 90, packages = apps, lastNudgedOnForNewRow = null)
        assertEquals("2026-10-14", db.lastNudgedOn())
        // Turning it off and on again doesn't reset the day either.
        db.save(enabled = false, budget = 90, packages = apps)
        db.save(enabled = true, budget = 90, packages = apps)
        assertEquals("2026-10-14", db.lastNudgedOn())
        assertFalse(db.withStore { it.claim("2026-10-14", 90, apps.toSet()) })
    }

    @Test
    fun concurrentClaimsFromSeparateConnectionsSucceedAtMostOnce() {
        db.save(enabled = true, budget = 60, packages = apps)
        val threads = 16
        val pool = Executors.newFixedThreadPool(threads)
        val start = CountDownLatch(1)
        val wins = AtomicInteger()
        repeat(threads) {
            pool.execute {
                start.await()
                if (db.withStore { it.claim("2026-10-14", 60, apps.toSet()) }) wins.incrementAndGet()
            }
        }
        start.countDown()
        pool.shutdown()
        assertTrue(pool.awaitTermination(30, TimeUnit.SECONDS))
        assertEquals(1, wins.get())
    }
}
