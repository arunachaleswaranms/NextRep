package com.nextrep.nextrep.sound

import android.app.NotificationManager
import android.media.AudioManager

/**
 * The completion sounds' native player (Phase 12G, addendum AD14 / AD15),
 * free of Android classes so the JVM tests can run it: [SoundEngine] wraps
 * `SoundPool`, [DeviceSoundState] the ringer and Do Not Disturb.
 *
 * - Loads only bundled files under `assets/sounds/`, once each.
 * - Plays a sound only once it has finished loading; until then, or after
 *   [release], a request is skipped, never queued.
 * - Stays silent unless the ringer is normal and Do Not Disturb is off
 *   ([SoundPolicy]). The engine's sonification stream is muted by the
 *   ringer as well; this check makes the rule explicit and the same on
 *   every manufacturer.
 * - Never asks for audio focus, so music and podcasts keep playing.
 *
 * Feedback only: every failure is a [PlayResult], never an exception.
 */
class CompletionSounds(
    private val newEngine: () -> SoundEngine,
    private val device: DeviceSoundState,
) {
    enum class PlayResult {
        PLAYED,
        NOT_READY,
        SILENCED_BY_RINGER,
        SILENCED_BY_DO_NOT_DISTURB,
        FAILED,
    }

    private var engine: SoundEngine? = null

    /** Sound id (`iceCrystal.habit`) → the engine's sample id. */
    private val samples = HashMap<String, Int>()

    /** Sample ids that finished loading successfully. */
    private val loaded = HashSet<Int>()

    /**
     * Loads every sound of [sounds] (id → bundled asset path) not loaded or
     * loading yet. Repeatable; a sound whose load failed is tried again.
     * Returns how many loads were started.
     */
    @Synchronized
    fun prepare(sounds: Map<String, String>): Int {
        val engine = engine ?: newEngine().also { created ->
            created.setOnLoaded { sample, ok -> onLoaded(created, sample, ok) }
            engine = created
        }
        var started = 0
        for ((id, asset) in sounds) {
            if (id in samples || !isBundledSound(asset)) continue
            val sample = try {
                engine.load(asset)
            } catch (e: Exception) {
                0
            }
            if (sample > 0) {
                samples[id] = sample
                started++
            }
        }
        return started
    }

    /** Plays [id] once, now, if it is loaded and the phone isn't silenced. */
    @Synchronized
    fun play(id: String): PlayResult {
        val engine = engine ?: return PlayResult.NOT_READY
        // Never prepared, still loading, or failed to load.
        val sample = samples[id] ?: return PlayResult.NOT_READY
        if (sample !in loaded) return PlayResult.NOT_READY
        val silenced = try {
            SoundPolicy.silencedBy(device.ringerMode(), device.interruptionFilter())
        } catch (e: Exception) {
            // The device state can't be read: stay quiet.
            SoundPolicy.Silence.DO_NOT_DISTURB
        }
        when (silenced) {
            SoundPolicy.Silence.RINGER -> return PlayResult.SILENCED_BY_RINGER
            SoundPolicy.Silence.DO_NOT_DISTURB -> return PlayResult.SILENCED_BY_DO_NOT_DISTURB
            null -> Unit
        }
        return try {
            if (engine.play(sample) != 0) PlayResult.PLAYED else PlayResult.FAILED
        } catch (e: Exception) {
            PlayResult.FAILED
        }
    }

    /** Frees the engine and forgets every sound. Repeatable. */
    @Synchronized
    fun release() {
        val released = engine ?: return
        engine = null
        samples.clear()
        loaded.clear()
        try {
            released.release()
        } catch (e: Exception) {
            // Nothing more to free.
        }
    }

    @Synchronized
    private fun onLoaded(from: SoundEngine, sample: Int, ok: Boolean) {
        // A late callback from an engine already released is ignored.
        if (from !== engine) return
        if (ok) {
            loaded.add(sample)
        } else {
            // Forget it (the next prepare loads it again) and free its slot.
            samples.values.remove(sample)
            try {
                from.unload(sample)
            } catch (e: Exception) {
                // Nothing more to free.
            }
        }
    }

    companion object {
        private val BUNDLED = Regex("""assets/sounds/[a-z_]+\.wav""")

        /** Only the app's own bundled sound files are ever opened. */
        fun isBundledSound(asset: String): Boolean = BUNDLED.matches(asset)
    }
}

/** When a completion sound must stay silent, whatever the stream does. */
object SoundPolicy {
    enum class Silence { RINGER, DO_NOT_DISTURB }

    /**
     * Null when a sound may play: the ringer is normal and Do Not Disturb
     * is off. Silent and vibrate modes, any Do Not Disturb mode (priority,
     * alarms only, total silence) and an unknown state are silent.
     */
    fun silencedBy(ringerMode: Int, interruptionFilter: Int): Silence? = when {
        ringerMode != AudioManager.RINGER_MODE_NORMAL -> Silence.RINGER
        interruptionFilter != NotificationManager.INTERRUPTION_FILTER_ALL -> Silence.DO_NOT_DISTURB
        else -> null
    }
}

/** `SoundPool`, as [CompletionSounds] uses it. */
interface SoundEngine {
    /** Called once per [load], with whether decoding succeeded. */
    fun setOnLoaded(listener: (sample: Int, ok: Boolean) -> Unit)

    /** Starts loading [asset]; the sample id, or 0 if it can't start. */
    fun load(asset: String): Int

    /** Frees a sample whose load failed. */
    fun unload(sample: Int)

    /** Plays [sample] once; the stream id, or 0 if it didn't start. */
    fun play(sample: Int): Int

    fun release()
}

/** The phone's sound state, read when a sound is about to play. */
interface DeviceSoundState {
    /** `AudioManager.getRingerMode()`. */
    fun ringerMode(): Int

    /** `NotificationManager.getCurrentInterruptionFilter()`. */
    fun interruptionFilter(): Int
}
