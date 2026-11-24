package com.nextrep.nextrep.sound

import android.app.NotificationManager
import android.media.AudioManager
import com.nextrep.nextrep.focusguard.FocusGuardChannel
import com.nextrep.nextrep.sound.CompletionSounds.PlayResult
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The completion-sound player's logic, with a fake `SoundPool` and a fake
 * ringer / Do Not Disturb state. What a real phone makes audible is checked
 * on the emulator (docs/PHASE_12G.md), not here.
 */
class CompletionSoundsTest {
    /** `SoundPool` as a test drives it: loads complete when told to. */
    private class FakeEngine : SoundEngine {
        var listener: ((Int, Boolean) -> Unit)? = null
        val loads = mutableListOf<String>()
        val plays = mutableListOf<Int>()
        val unloaded = mutableListOf<Int>()
        var released = 0
        var failLoadOf: String? = null
        var playReturns = 7
        var throwOnPlay = false
        private var next = 1

        override fun setOnLoaded(listener: (sample: Int, ok: Boolean) -> Unit) {
            this.listener = listener
        }

        override fun load(asset: String): Int {
            if (asset == failLoadOf) throw java.io.FileNotFoundException(asset)
            loads.add(asset)
            return next++
        }

        override fun play(sample: Int): Int {
            if (throwOnPlay) throw IllegalStateException("released")
            plays.add(sample)
            return playReturns
        }

        override fun unload(sample: Int) {
            unloaded.add(sample)
        }

        override fun release() {
            released++
        }

        fun finishAll(ok: Boolean = true) {
            for (sample in 1 until next) listener!!.invoke(sample, ok)
        }
    }

    private class FakeDevice(
        var ringer: Int = AudioManager.RINGER_MODE_NORMAL,
        var filter: Int = NotificationManager.INTERRUPTION_FILTER_ALL,
        var fail: Boolean = false,
    ) : DeviceSoundState {
        override fun ringerMode(): Int {
            if (fail) throw SecurityException("unavailable")
            return ringer
        }

        override fun interruptionFilter(): Int = filter
    }

    private val catalogue = mapOf(
        "iceCrystal.habit" to "assets/sounds/ice_crystal_habit.wav",
        "iceCrystal.perfectDay" to "assets/sounds/ice_crystal_perfect_day.wav",
        "summitSpark.habit" to "assets/sounds/summit_spark_habit.wav",
        "summitSpark.perfectDay" to "assets/sounds/summit_spark_perfect_day.wav",
        "warmEmber.habit" to "assets/sounds/warm_ember_habit.wav",
        "warmEmber.perfectDay" to "assets/sounds/warm_ember_perfect_day.wav",
    )

    private val engines = mutableListOf<FakeEngine>()
    private val device = FakeDevice()
    private val sounds = CompletionSounds(
        newEngine = { FakeEngine().also { engines.add(it) } },
        device = device,
    )

    private fun ready(): FakeEngine {
        sounds.prepare(catalogue)
        return engines.last().also { it.finishAll() }
    }

    @Test
    fun preparesEveryBundledSoundOnce() {
        assertEquals(6, sounds.prepare(catalogue))
        assertEquals(0, sounds.prepare(catalogue))
        assertEquals(1, engines.size)
        assertEquals(catalogue.values.toList(), engines[0].loads)
    }

    @Test
    fun opensOnlyTheAppsOwnSoundFiles() {
        for (asset in listOf(
            "assets/sounds/../../flutter_assets/kernel_blob.bin",
            "assets/sounds/ice.mp3",
            "/data/data/x/file.wav",
            "assets/images/ice_crystal_habit.wav",
            "assets/sounds/Ice.wav",
            "",
        )) {
            assertFalse(asset, CompletionSounds.isBundledSound(asset))
        }
        assertEquals(0, sounds.prepare(mapOf("x" to "assets/sounds/../secret.wav")))
        assertTrue(engines[0].loads.isEmpty())
        for (asset in catalogue.values) assertTrue(asset, CompletionSounds.isBundledSound(asset))
    }

    @Test
    fun playsALoadedSoundOnce() {
        val engine = ready()
        assertEquals(PlayResult.PLAYED, sounds.play("iceCrystal.habit"))
        assertEquals(PlayResult.PLAYED, sounds.play("warmEmber.perfectDay"))
        assertEquals(listOf(1, 6), engine.plays)
    }

    @Test
    fun skipsASoundThatIsNotLoadedYetAndNeverPlaysItLater() {
        assertEquals(PlayResult.NOT_READY, sounds.play("iceCrystal.habit")) // nothing prepared
        sounds.prepare(catalogue)
        val engine = engines[0]
        assertEquals(PlayResult.NOT_READY, sounds.play("iceCrystal.habit")) // still loading
        engine.finishAll()
        assertTrue("nothing queued", engine.plays.isEmpty())
        assertEquals(PlayResult.PLAYED, sounds.play("iceCrystal.habit"))
        assertEquals(listOf(1), engine.plays)
    }

    @Test
    fun anUnknownSoundIsSkipped() {
        val engine = ready()
        assertEquals(PlayResult.NOT_READY, sounds.play("loud.alarm"))
        assertTrue(engine.plays.isEmpty())
    }

    @Test
    fun aFailedLoadIsSkippedAndRetriedByTheNextPrepare() {
        sounds.prepare(catalogue)
        val engine = engines[0]
        engine.finishAll(ok = false)
        assertEquals(PlayResult.NOT_READY, sounds.play("iceCrystal.habit"))
        assertEquals((1..6).toList(), engine.unloaded)
        assertEquals(6, sounds.prepare(catalogue))
        assertEquals(12, engine.loads.size)
    }

    @Test
    fun aMissingAssetDoesNotStopTheOthers() {
        sounds.prepare(emptyMap()) // creates the engine
        engines[0].failLoadOf = "assets/sounds/summit_spark_habit.wav"
        assertEquals(5, sounds.prepare(catalogue))
        engines[0].finishAll()
        assertEquals(PlayResult.NOT_READY, sounds.play("summitSpark.habit"))
        assertEquals(PlayResult.PLAYED, sounds.play("summitSpark.perfectDay"))
    }

    @Test
    fun silentAndVibrateModesPlayNothing() {
        val engine = ready()
        for (mode in listOf(AudioManager.RINGER_MODE_SILENT, AudioManager.RINGER_MODE_VIBRATE)) {
            device.ringer = mode
            assertEquals(PlayResult.SILENCED_BY_RINGER, sounds.play("iceCrystal.habit"))
        }
        assertTrue(engine.plays.isEmpty())
        device.ringer = AudioManager.RINGER_MODE_NORMAL
        assertEquals(PlayResult.PLAYED, sounds.play("iceCrystal.habit"))
    }

    @Test
    fun everyDoNotDisturbModePlaysNothing() {
        val engine = ready()
        for (filter in listOf(
            NotificationManager.INTERRUPTION_FILTER_PRIORITY,
            NotificationManager.INTERRUPTION_FILTER_ALARMS,
            NotificationManager.INTERRUPTION_FILTER_NONE,
            NotificationManager.INTERRUPTION_FILTER_UNKNOWN,
        )) {
            device.filter = filter
            assertEquals("filter $filter", PlayResult.SILENCED_BY_DO_NOT_DISTURB, sounds.play("iceCrystal.habit"))
        }
        assertTrue(engine.plays.isEmpty())
    }

    @Test
    fun anUnreadableDeviceStateStaysQuiet() {
        val engine = ready()
        device.fail = true
        assertEquals(PlayResult.SILENCED_BY_DO_NOT_DISTURB, sounds.play("iceCrystal.habit"))
        assertTrue(engine.plays.isEmpty())
    }

    @Test
    fun thePolicy() {
        val normal = AudioManager.RINGER_MODE_NORMAL
        val all = NotificationManager.INTERRUPTION_FILTER_ALL
        assertNull(SoundPolicy.silencedBy(normal, all))
        assertEquals(SoundPolicy.Silence.RINGER, SoundPolicy.silencedBy(AudioManager.RINGER_MODE_SILENT, all))
        assertEquals(SoundPolicy.Silence.RINGER, SoundPolicy.silencedBy(AudioManager.RINGER_MODE_VIBRATE, all))
        // Both: the ringer is reported first.
        assertEquals(
            SoundPolicy.Silence.RINGER,
            SoundPolicy.silencedBy(AudioManager.RINGER_MODE_SILENT, NotificationManager.INTERRUPTION_FILTER_NONE),
        )
        assertEquals(
            SoundPolicy.Silence.DO_NOT_DISTURB,
            SoundPolicy.silencedBy(normal, NotificationManager.INTERRUPTION_FILTER_PRIORITY),
        )
    }

    @Test
    fun aPlaybackFailureIsReportedNotThrown() {
        val engine = ready()
        engine.playReturns = 0
        assertEquals(PlayResult.FAILED, sounds.play("iceCrystal.habit"))
        engine.throwOnPlay = true
        assertEquals(PlayResult.FAILED, sounds.play("iceCrystal.habit"))
    }

    @Test
    fun releaseFreesTheEngineAndForgetsEverySound() {
        val engine = ready()
        sounds.release()
        assertEquals(1, engine.released)
        assertEquals(PlayResult.NOT_READY, sounds.play("iceCrystal.habit"))
        assertTrue(engine.plays.isEmpty())
        sounds.release() // repeatable
        assertEquals(1, engine.released)
    }

    @Test
    fun aLateLoadCallbackFromAReleasedEngineIsIgnored() {
        sounds.prepare(catalogue)
        val old = engines[0]
        sounds.release()
        old.finishAll()
        sounds.prepare(catalogue)
        assertEquals(PlayResult.NOT_READY, sounds.play("iceCrystal.habit"))
        assertTrue(old.plays.isEmpty())
    }

    @Test
    fun preparingAgainAfterReleaseStartsAFreshEngine() {
        ready()
        sounds.release()
        val second = ready()
        assertEquals(2, engines.size)
        assertEquals(6, second.loads.size)
        assertEquals(PlayResult.PLAYED, sounds.play("summitSpark.habit"))
        assertEquals(listOf(3), second.plays)
        assertEquals(1, engines[0].released)
        assertEquals(0, second.released)
    }

    @Test
    fun itsOwnChannelNeverCollidesWithFocusGuards() {
        assertEquals("com.nextrep.nextrep/completion_sound", CompletionSoundChannel.NAME)
        assertNotEquals(FocusGuardChannel.NAME, CompletionSoundChannel.NAME)
        assertFalse(CompletionSoundChannel.NAME.startsWith(FocusGuardChannel.NAME))
        assertFalse(FocusGuardChannel.NAME.startsWith(CompletionSoundChannel.NAME))
    }
}
