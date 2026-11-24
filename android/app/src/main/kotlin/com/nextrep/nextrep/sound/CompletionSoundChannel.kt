package com.nextrep.nextrep.sound

import android.app.NotificationManager
import android.content.Context
import android.content.pm.ApplicationInfo
import android.content.res.AssetManager
import android.media.AudioAttributes
import android.media.AudioManager
import android.media.SoundPool
import android.util.Log
import io.flutter.FlutterInjector
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * The Flutter side's completion-sound player
 * (`lib/data/native_sound_player.dart`): `prepare` loads the bundled
 * sounds, `play` plays one. Its own channel, separate from Focus Guard's.
 *
 * Runs on the main thread: loading only opens an asset and hands it to
 * `SoundPool`, which decodes on its own thread. No permission, no network,
 * no notification channel, no audio focus.
 */
class CompletionSoundChannel(
    context: Context,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler {
    private val app = context.applicationContext
    private val channel = MethodChannel(messenger, NAME)
    private val debuggable = app.applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE != 0
    private val sounds = CompletionSounds(
        newEngine = { SoundPoolEngine(app.assets) },
        device = AndroidDeviceSoundState(app),
    )

    init {
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "prepare" -> {
                val requested = call.argument<Map<String, String>>("sounds")
                if (requested == null) {
                    result.error("bad_arguments", "prepare needs sounds", null)
                    return
                }
                result.success(sounds.prepare(requested))
            }
            "play" -> {
                val id = call.argument<String>("sound")
                if (id == null) {
                    result.error("bad_arguments", "play needs sound", null)
                    return
                }
                val outcome = sounds.play(id)
                // Debug builds only, for device qualification: the sound's
                // id and what happened, nothing else.
                if (debuggable) Log.d(TAG, "play $id: $outcome")
                result.success(outcome.name)
            }
            else -> result.notImplemented()
        }
    }

    fun dispose() {
        channel.setMethodCallHandler(null)
        sounds.release()
    }

    companion object {
        const val NAME = "com.nextrep.nextrep/completion_sound"
        private const val TAG = "NextRepSound"
    }
}

/**
 * `SoundPool` with sonification audio attributes: the system-sound stream,
 * which follows the ringer (silent and vibrate mute it), its volume and Do
 * Not Disturb. One stream at most, so two sounds never overlap. `SoundPool`
 * requests no audio focus, so other audio is never paused or ducked.
 */
class SoundPoolEngine(private val assets: AssetManager) : SoundEngine {
    private val pool: SoundPool = SoundPool.Builder()
        .setMaxStreams(1)
        .setAudioAttributes(
            AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_ASSISTANCE_SONIFICATION)
                .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                .build(),
        )
        .build()

    override fun setOnLoaded(listener: (sample: Int, ok: Boolean) -> Unit) {
        pool.setOnLoadCompleteListener { _, sample, status -> listener(sample, status == 0) }
    }

    override fun load(asset: String): Int {
        val key = FlutterInjector.instance().flutterLoader().getLookupKeyForAsset(asset)
        // SoundPool keeps its own duplicate of the descriptor.
        return assets.openFd(key).use { pool.load(it, 1) }
    }

    override fun unload(sample: Int) {
        pool.unload(sample)
    }

    override fun play(sample: Int): Int = pool.play(sample, 1f, 1f, 1, 0, 1f)

    override fun release() = pool.release()
}

/** The live ringer mode and Do Not Disturb state. Reading needs no permission. */
class AndroidDeviceSoundState(context: Context) : DeviceSoundState {
    private val audio = context.getSystemService(AudioManager::class.java)
    private val notifications = context.getSystemService(NotificationManager::class.java)

    override fun ringerMode(): Int = audio.ringerMode

    override fun interruptionFilter(): Int = notifications.currentInterruptionFilter
}
