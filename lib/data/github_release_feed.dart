import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

import '../domain/update/official_source.dart';
import '../domain/update/release_feed.dart';

/// [ReleaseFeed] over HTTPS: one GET to GitHub's "latest release" endpoint
/// of the official repository. NextRep's only network request, made only
/// when the user taps "Check for updates" (see `UpdateCheckController`).
///
/// * one request at a time: a call made while one is in flight (About left
///   and reopened, for example) joins it instead of sending another
/// * a new client per request, closed afterwards (which also aborts a
///   request still running at the timeout)
/// * [timeout] for the whole exchange, connecting included
/// * at most [maxBytes] of body, read as it streams; larger is rejected
/// * redirects are never followed, so it can't be sent to another host
/// * the platform's TLS certificate checks, unmodified
/// * no credentials, cookies or body: only the headers below
final class GitHubReleaseFeed implements ReleaseFeed {
  GitHubReleaseFeed({
    http.Client Function()? client,
    this.timeout = const Duration(seconds: 10),
    this.maxBytes = OfficialSource.maxMetadataBytes,
  }) : _newClient = client ?? (() => _platformClient(timeout));

  final http.Client Function() _newClient;
  final Duration timeout;
  final int maxBytes;
  Future<ReleaseFeedResponse>? _inFlight;

  static const headers = {
    'Accept': 'application/vnd.github+json',
    'X-GitHub-Api-Version': '2022-11-28',
    'User-Agent': 'NextRep-Manual-Updates',
  };

  static http.Client _platformClient(Duration timeout) =>
      IOClient(HttpClient()..connectionTimeout = timeout);

  @override
  Future<ReleaseFeedResponse> fetchLatest() =>
      _inFlight ??= _fetchOnce().whenComplete(() => _inFlight = null);

  Future<ReleaseFeedResponse> _fetchOnce() async {
    final client = _newClient();
    try {
      return await _fetch(client).timeout(timeout);
    } on ReleaseFeedException {
      rethrow;
    } on TimeoutException {
      throw const ReleaseFeedUnavailable('timed out');
    } on TlsException {
      throw const ReleaseFeedUnavailable('TLS failure');
    } on Exception catch (error) {
      // Socket, DNS, HTTP-level and client errors. Only the type is kept:
      // nothing from the exchange is logged.
      throw ReleaseFeedUnavailable(error.runtimeType.toString());
    } finally {
      client.close();
    }
  }

  Future<ReleaseFeedResponse> _fetch(http.Client client) async {
    final request = http.Request('GET', OfficialSource.latestReleaseApi)
      ..followRedirects = false
      ..headers.addAll(headers);
    final response = await client.send(request);
    final declared = response.contentLength;
    if (declared != null && declared > maxBytes) {
      throw const ReleaseFeedTooLarge();
    }
    final body = BytesBuilder(copy: false);
    await for (final chunk in response.stream) {
      body.add(chunk);
      if (body.length > maxBytes) throw const ReleaseFeedTooLarge();
    }
    return ReleaseFeedResponse(
      statusCode: response.statusCode,
      headers: response.headers,
      body: body.takeBytes(),
    );
  }
}
