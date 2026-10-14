package com.nextrep.nextrep.focusguard

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import com.nextrep.nextrep.MainActivity
import com.nextrep.nextrep.R

/**
 * Focus Guard's one daily nudge, posted natively so it works with no Flutter
 * engine running. Its own channel (`focus_guard`), so it can be silenced
 * separately from the reminders. The copy names the budget only: never an
 * app, an amount of usage or anything else personal.
 *
 * Posted with a tag, so its id can't collide with the reminder plugin's
 * untagged ids (100–113, 200–213, 300–364).
 */
object FocusGuardNotifier {
    const val CHANNEL_ID = "focus_guard"
    const val NOTIFICATION_TAG = "focus_guard"
    const val NOTIFICATION_ID = 1

    /** The tap's intent action; MainActivity hands it to Flutter. */
    const val ACTION_OPEN = "com.nextrep.nextrep.action.FOCUS_GUARD_NUDGE"

    /** Notifications allowed for NextRep and the Focus Guard channel not blocked. */
    fun nudgesAllowed(context: Context): Boolean {
        val manager = context.getSystemService(NotificationManager::class.java) ?: return false
        if (!manager.areNotificationsEnabled()) return false
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = manager.getNotificationChannel(CHANNEL_ID)
            if (channel != null && channel.importance == NotificationManager.IMPORTANCE_NONE) {
                return false
            }
        }
        return true
    }

    fun body(budgetMinutes: Int): String =
        "You've reached today's $budgetMinutes-minute Focus Guard budget. " +
            "Time to come back to your Arc?"

    /** Throws if the notification can't be posted. */
    fun post(context: Context, budgetMinutes: Int) {
        val manager = context.getSystemService(NotificationManager::class.java)
            ?: throw IllegalStateException("NotificationManager unavailable")
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            manager.createNotificationChannel(
                NotificationChannel(
                    CHANNEL_ID,
                    "Focus Guard",
                    NotificationManager.IMPORTANCE_DEFAULT,
                ).apply {
                    description =
                        "One gentle reminder a day when your selected apps reach " +
                        "their combined daily budget."
                },
            )
            Notification.Builder(context, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(context)
        }
        val body = body(budgetMinutes)
        val tap = PendingIntent.getActivity(
            context,
            0,
            Intent(context, MainActivity::class.java)
                .setAction(ACTION_OPEN)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        val notification = builder
            .setSmallIcon(R.drawable.ic_stat_reminder)
            .setContentTitle("Focus Guard")
            .setContentText(body)
            .setStyle(Notification.BigTextStyle().bigText(body))
            .setCategory(Notification.CATEGORY_REMINDER)
            .setContentIntent(tap)
            .setAutoCancel(true)
            .setShowWhen(true)
            .build()
        manager.notify(NOTIFICATION_TAG, NOTIFICATION_ID, notification)
    }

    /** Whether [intent] is a tap on the nudge (not a relaunch from Recents). */
    fun isNudgeTap(intent: Intent?): Boolean =
        intent?.action == ACTION_OPEN &&
            intent.flags and Intent.FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY == 0
}
