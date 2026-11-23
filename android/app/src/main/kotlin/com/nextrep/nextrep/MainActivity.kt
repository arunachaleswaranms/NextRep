package com.nextrep.nextrep

import android.content.Intent
import com.nextrep.nextrep.focusguard.FocusGuardChannel
import com.nextrep.nextrep.focusguard.FocusGuardNotifier
import com.nextrep.nextrep.sound.CompletionSoundChannel
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    private var focusGuard: FocusGuardChannel? = null
    private var completionSounds: CompletionSoundChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        focusGuard = FocusGuardChannel(this, flutterEngine.dartExecutor.binaryMessenger)
        // Completion sounds (Phase 12G): a separate channel; Focus Guard's is
        // unchanged.
        completionSounds = CompletionSoundChannel(this, flutterEngine.dartExecutor.binaryMessenger)
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        focusGuard?.dispose()
        focusGuard = null
        completionSounds?.dispose()
        completionSounds = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    // A tap on the Focus Guard nudge while NextRep is running. A tap that
    // launches the activity is picked up by Flutter at startup instead.
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        if (FocusGuardNotifier.isNudgeTap(intent)) focusGuard?.nudgeTapped()
    }
}
