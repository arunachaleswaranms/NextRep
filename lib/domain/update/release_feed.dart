import 'dart:typed_data';

/// GitHub's answer to the "latest release" request, as received: no
/// redirect was followed and the body is within the size limit.
final class ReleaseFeedResponse {
  const ReleaseFeedResponse({
    required this.statusCode,
    required this.body,
    this.headers = const {},
  });

  final int statusCode;

  /// Response headers, names in lower case.
  final Map<String, String> headers;
  final Uint8List body;

  String? get contentType => headers['content-type'];
}

/// Why no usable response arrived.
sealed class ReleaseFeedException implements Exception {
  const ReleaseFeedException();
}

/// No answer: offline, DNS, refused, TLS failure or timeout.
final class ReleaseFeedUnavailable extends ReleaseFeedException {
  const ReleaseFeedUnavailable(this.reason);

  final String reason;

  @override
  String toString() => 'ReleaseFeedUnavailable: $reason';
}

/// An answer too large to be release metadata. It was not read in full.
final class ReleaseFeedTooLarge extends ReleaseFeedException {
  const ReleaseFeedTooLarge();

  @override
  String toString() => 'ReleaseFeedTooLarge';
}

/// Reads the official repository's latest release metadata, once per
/// call. Only ever called when the user taps "Check for updates".
abstract interface class ReleaseFeed {
  /// Throws a [ReleaseFeedException] when no usable response arrived.
  Future<ReleaseFeedResponse> fetchLatest();
}
