import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../core/errors/app_failure.dart';
import '../core/errors/error_reporter.dart';

/// How the system share sheet closed. NextRep never acts on it beyond
/// letting the user share again: sharing earns nothing and is not tracked.
enum ShareOutcome {
  /// The user picked a target.
  shared,

  /// The user closed the sheet without sharing.
  dismissed,

  /// The platform doesn't report what happened.
  unavailable,
}

/// One file to share. Share cards are always PNG images.
final class ShareFile {
  const ShareFile.png({required this.bytes, required this.name})
    : mimeType = 'image/png';

  final Uint8List bytes;

  /// File name shown to the receiving app, e.g. `nextrep-day-24.png`.
  final String name;
  final String mimeType;
}

/// The operating system's share sheet: the only way a share card leaves the
/// app, and only when the user asks.
abstract interface class ShareGateway {
  /// Offers [file], with short accompanying [text], in the system share
  /// sheet. [origin] anchors the iPad popover. Throws if the sheet couldn't
  /// be opened.
  Future<ShareOutcome> share(
    ShareFile file, {
    required String text,
    Rect? origin,
  });
}

/// [ShareGateway] through `share_plus`.
///
/// The image is staged in its own folder in the app's private cache and
/// deleted again once the sheet closes; no storage or media permission is
/// involved and nothing goes to the gallery. On Android `share_plus` hands
/// receivers a copy in `cache/share_plus/` through its FileProvider and
/// clears that folder on the next share; the OS may also reclaim the cache.
/// On iOS, Save Image and Assign to Contact are left out of the sheet, so
/// sharing never needs photo-library or contacts access.
final class SystemShareGateway implements ShareGateway {
  const SystemShareGateway();

  static const _stagingFolder = 'nextrep_share';

  @override
  Future<ShareOutcome> share(
    ShareFile file, {
    required String text,
    Rect? origin,
  }) async {
    final cache = await getTemporaryDirectory();
    final staging = Directory('${cache.path}/$_stagingFolder');
    try {
      // A card left behind by an interrupted share goes first.
      if (await staging.exists()) await staging.delete(recursive: true);
      await staging.create(recursive: true);
      final staged = File('${staging.path}/${file.name}');
      await staged.writeAsBytes(file.bytes, flush: true);
      final result = await SharePlus.instance.share(
        ShareParams(
          files: [XFile(staged.path, mimeType: file.mimeType, name: file.name)],
          text: text,
          sharePositionOrigin: origin,
          excludedCupertinoActivities: const [
            CupertinoActivityType.saveToCameraRoll,
            CupertinoActivityType.assignToContact,
          ],
        ),
      );
      return switch (result.status) {
        ShareResultStatus.success => ShareOutcome.shared,
        ShareResultStatus.dismissed => ShareOutcome.dismissed,
        ShareResultStatus.unavailable => ShareOutcome.unavailable,
      };
    } finally {
      await _remove(staging);
    }
  }

  /// Best effort: the OS clears the cache eventually anyway.
  static Future<void> _remove(Directory staging) async {
    try {
      if (await staging.exists()) await staging.delete(recursive: true);
    } catch (error, stackTrace) {
      ErrorReporter.report(toAppFailure(error, stackTrace), context: 'share');
    }
  }
}
