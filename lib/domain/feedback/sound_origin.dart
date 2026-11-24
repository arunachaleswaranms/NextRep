/// Where a sound request came from, and whether that place may still
/// sound (Phase 12G review correction G-R1).
///
/// A screen that makes sounds (Today, Sound & Feedback) hands one to each
/// request. It stays active only while the screen is what the user is
/// looking at, in the foreground, for the same Arc and app epoch, and is
/// cancelled the moment that stops being true. The feedback engine checks
/// it after its asynchronous setting read and again when it commits to
/// playback, so a request that outlived its screen is dropped.
///
/// Cancelling is permanent and idempotent: a cancelled origin never becomes
/// active again. When the screen becomes eligible again it makes a new
/// origin, so a request made before the user left stays dropped even if
/// they come back to the same screen and Arc. Nothing is queued or retried.
final class SoundOrigin {
  /// An active origin.
  SoundOrigin();

  /// An origin that is already over: what a screen that isn't eligible
  /// hands out.
  SoundOrigin.cancelled() : _active = false;

  bool _active = true;

  /// Whether a request from here may still start a sound.
  bool get isActive => _active;

  /// Drops every request from here that hasn't started yet. A sound that
  /// already started is not stopped.
  void cancel() => _active = false;
}
