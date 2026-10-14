package com.nextrep.nextrep.focusguard

import android.app.Activity
import android.content.Intent
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

/**
 * The Flutter side's view of Focus Guard (`lib/data/android_focus_guard.dart`).
 *
 * Runs in the main process and never opens the database: settings are
 * Drift's, read and written by Dart. Slow calls run off the main thread.
 * Errors carry a generic code only, never a package name or an amount.
 */
class FocusGuardChannel(
    private val activity: Activity,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler {
    private val channel = MethodChannel(messenger, NAME)
    private val worker: ExecutorService = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())

    init {
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        val context = activity.applicationContext
        when (call.method) {
            "usageAccess" -> background(result) {
                if (FocusGuardUsage.usageAccessGranted(context)) "granted" else "notGranted"
            }
            // Only ever invoked from the user's tap on the grant action.
            "openUsageAccessSettings" -> result.success(FocusGuardUsage.openUsageAccessSettings(activity))
            "launchableApps" -> background(result) { FocusGuardUsage.launchableApps(context) }
            "foregroundTime" -> {
                val packages = call.argument<List<String>>("packages")?.toSet()
                val from = call.argument<Number>("from")?.toLong()
                val to = call.argument<Number>("to")?.toLong()
                if (packages == null || from == null || to == null) {
                    result.error("bad_arguments", "foregroundTime needs packages, from, to", null)
                    return
                }
                background(result) { FocusGuardUsage.foregroundMillis(context, packages, from, to) }
            }
            "nudgesAllowed" -> result.success(FocusGuardNotifier.nudgesAllowed(context))
            "ensureScheduled" -> background(result) {
                FocusGuardScheduler.ensureScheduled(context)
                null
            }
            "cancelSchedule" -> background(result) {
                FocusGuardScheduler.cancel(context)
                null
            }
            "takeLaunchNudgeTap" -> result.success(takeLaunchNudgeTap())
            else -> result.notImplemented()
        }
    }

    /**
     * Whether the activity was opened by tapping the nudge. Answers true once:
     * the intent's action is then cleared, so a recreated activity doesn't
     * route again.
     */
    private fun takeLaunchNudgeTap(): Boolean {
        val intent = activity.intent
        if (!FocusGuardNotifier.isNudgeTap(intent)) return false
        activity.intent = Intent(intent).setAction(Intent.ACTION_MAIN)
        return true
    }

    /** The nudge was tapped while the Flutter UI is running. */
    fun nudgeTapped() {
        channel.invokeMethod("nudgeTapped", null)
    }

    fun dispose() {
        channel.setMethodCallHandler(null)
        worker.shutdown()
    }

    private fun background(result: MethodChannel.Result, body: () -> Any?) {
        worker.execute {
            try {
                val value = body()
                main.post { result.success(value) }
            } catch (e: Exception) {
                main.post { result.error("focus_guard_failed", e.javaClass.simpleName, null) }
            }
        }
    }

    companion object {
        const val NAME = "com.nextrep.nextrep/focus_guard"
    }
}
