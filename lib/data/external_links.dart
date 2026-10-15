import 'package:url_launcher/url_launcher.dart';

import '../core/errors/app_failure.dart';
import '../core/errors/error_reporter.dart';
import '../domain/update/official_source.dart';

/// Opens official NextRep pages in the device's own browser, only when the
/// user taps a link. Never an in-app WebView, and never a download.
abstract interface class ExternalLinks {
  /// Opens [page]. False when it isn't an official page
  /// ([OfficialSource.isTrustedPage]) or no browser could open it.
  Future<bool> open(Uri page);
}

/// [ExternalLinks] through `url_launcher`, in an external application.
final class SystemExternalLinks implements ExternalLinks {
  const SystemExternalLinks();

  @override
  Future<bool> open(Uri page) async {
    if (!OfficialSource.isTrustedPage(page)) return false;
    try {
      return await launchUrl(page, mode: LaunchMode.externalApplication);
    } catch (error, stackTrace) {
      ErrorReporter.report(toAppFailure(error, stackTrace), context: 'links');
      return false;
    }
  }
}
