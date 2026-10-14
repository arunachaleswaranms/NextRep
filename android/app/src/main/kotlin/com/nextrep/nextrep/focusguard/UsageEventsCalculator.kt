package com.nextrep.nextrep.focusguard

/**
 * One UsageStats event, reduced to what Focus Guard reads. Plain data, so the
 * calculation is tested on the JVM without a device.
 */
data class UsageEvent(
    val packageName: String?,
    val className: String?,
    val type: Int,
    val timeMs: Long,
)

/**
 * Foreground time per package from a chronological UsageStats event stream:
 * the method qualified in Phase 11A (docs/PHASE_11A.md, "UsageStats results").
 *
 * - A package's session opens on the first ACTIVITY_RESUMED while none of its
 *   activities is resumed, and closes when the last one is paused or stopped.
 *   Several resumed activities of one package (split screen) count once.
 * - The stream starts [queryStart], a little before the window, so a session
 *   that began before local midnight is counted from midnight. If the first
 *   activity event seen for a package is an unmatched ACTIVITY_PAUSED, the
 *   package was already in the foreground: since the stream began, or since
 *   the last screen-off, shutdown or startup, whichever is later. Other event
 *   types of the package (notifications, standby buckets...) are ignored.
 * - The screen turning off or the device shutting down closes every session:
 *   nothing counts while the user isn't using the phone. After a device
 *   startup, sessions left open by missing events are dropped, not counted.
 * - A session still open at the end of the window counts up to its end.
 * - Only time inside the window counts; no package exceeds the window.
 *
 * Nothing here stores anything.
 */
object UsageEventsCalculator {
    // android.app.usage.UsageEvents.Event values (public, stable API).
    /** ACTIVITY_RESUMED (MOVE_TO_FOREGROUND before API 29). */
    const val ACTIVITY_RESUMED = 1

    /** ACTIVITY_PAUSED (MOVE_TO_BACKGROUND before API 29). */
    const val ACTIVITY_PAUSED = 2

    /** SCREEN_NON_INTERACTIVE, API 28+. */
    const val SCREEN_NON_INTERACTIVE = 16

    /** ACTIVITY_STOPPED, API 29+. */
    const val ACTIVITY_STOPPED = 23

    /** DEVICE_SHUTDOWN, API 29+. */
    const val DEVICE_SHUTDOWN = 26

    /** DEVICE_STARTUP, API 29+. */
    const val DEVICE_STARTUP = 27

    private class Session {
        val resumed = HashSet<String>()
        var since = 0L
    }

    fun foregroundMillis(
        events: Iterator<UsageEvent>,
        packages: Set<String>,
        queryStart: Long,
        windowStart: Long,
        windowEnd: Long,
    ): Map<String, Long> {
        require(queryStart <= windowStart && windowStart <= windowEnd)
        val totals = HashMap<String, Long>()
        val open = HashMap<String, Session>()
        val seen = HashSet<String>()
        // The latest moment nothing was in the foreground.
        var boundary = queryStart

        fun add(pkg: String, from: Long, to: Long) {
            val start = maxOf(from, windowStart)
            val end = minOf(to, windowEnd)
            if (end > start) totals[pkg] = (totals[pkg] ?: 0L) + (end - start)
        }

        fun closeAll(at: Long, count: Boolean) {
            if (count) {
                for ((pkg, session) in open) {
                    if (session.resumed.isNotEmpty()) add(pkg, session.since, at)
                }
            }
            open.clear()
        }

        for (event in events) {
            if (event.timeMs > windowEnd) break
            when (event.type) {
                SCREEN_NON_INTERACTIVE, DEVICE_SHUTDOWN -> {
                    closeAll(event.timeMs, count = true)
                    boundary = maxOf(boundary, event.timeMs)
                    continue
                }
                DEVICE_STARTUP -> {
                    closeAll(event.timeMs, count = false)
                    boundary = maxOf(boundary, event.timeMs)
                    continue
                }
                ACTIVITY_RESUMED, ACTIVITY_PAUSED, ACTIVITY_STOPPED -> Unit
                else -> continue
            }
            val pkg = event.packageName ?: continue
            if (pkg !in packages) continue
            val activity = event.className ?: ""
            val firstEvent = seen.add(pkg)
            when (event.type) {
                ACTIVITY_RESUMED -> {
                    val session = open.getOrPut(pkg) { Session() }
                    if (session.resumed.isEmpty()) session.since = event.timeMs
                    session.resumed.add(activity)
                }
                ACTIVITY_PAUSED, ACTIVITY_STOPPED -> {
                    val session = open[pkg]
                    if (session != null && session.resumed.remove(activity)) {
                        if (session.resumed.isEmpty()) {
                            add(pkg, session.since, event.timeMs)
                            open.remove(pkg)
                        }
                    } else if (firstEvent && event.type == ACTIVITY_PAUSED) {
                        // In the foreground since before the stream began
                        // (or the last time nothing could be).
                        add(pkg, boundary, event.timeMs)
                    }
                }
            }
        }
        closeAll(windowEnd, count = true)

        val window = windowEnd - windowStart
        return totals.mapValues { (_, ms) -> minOf(ms, window) }
    }
}
