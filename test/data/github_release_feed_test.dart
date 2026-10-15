import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:nextrep/data/github_release_feed.dart';
import 'package:nextrep/domain/update/release_feed.dart';

import '../support/updates.dart';

/// The transport, over a fake client: never the live GitHub API.
void main() {
  late FakeGitHubClient github;
  late int clientsMade;

  GitHubReleaseFeed feed({
    Duration timeout = const Duration(seconds: 10),
    int maxBytes = 256 * 1024,
  }) => GitHubReleaseFeed(
    client: () {
      clientsMade++;
      return github;
    },
    timeout: timeout,
    maxBytes: maxBytes,
  );

  setUp(() {
    github = FakeGitHubClient();
    clientsMade = 0;
  });

  Matcher unavailable(String reason) => throwsA(
    isA<ReleaseFeedUnavailable>().having((e) => e.reason, 'reason', reason),
  );

  test('constructing the feed sends nothing and makes no client', () {
    feed();
    GitHubReleaseFeed(); // the production default, too
    expect(clientsMade, 0);
    expect(github.requests, isEmpty);
  });

  test('one fetch: one GET to the official endpoint, only the expected '
      'headers, no body, no redirects; the client is closed', () async {
    final response = await feed().fetchLatest();
    expect(response.statusCode, 200);
    expect(github.requests, hasLength(1));
    final request = github.requests.single as http.Request;
    expect(request.method, 'GET');
    expect(
      request.url.toString(),
      'https://api.github.com/repos/arunachaleswaranms/NextRep/releases/latest',
    );
    expect(request.headers, {
      'Accept': 'application/vnd.github+json',
      'X-GitHub-Api-Version': '2022-11-28',
      'User-Agent': 'NextRep-Manual-Updates',
    });
    expect(request.body, isEmpty);
    expect(request.followRedirects, isFalse);
    expect(clientsMade, 1);
    expect(github.closes, 1);
  });

  test('every fetch uses a new client and closes it', () async {
    final releases = feed();
    await releases.fetchLatest();
    await releases.fetchLatest();
    expect(github.requests, hasLength(2));
    expect(clientsMade, 2);
    expect(github.closes, 2);
  });

  test('a fetch while one is in flight joins it: one request', () async {
    final pending = github.hold();
    final releases = feed();
    final first = releases.fetchLatest();
    final second = releases.fetchLatest();
    await Future<void>.delayed(Duration.zero);
    expect(github.requests, hasLength(1));
    pending.complete(githubResponse(200, json: releaseJson()));
    expect((await first).statusCode, 200);
    expect((await second).statusCode, 200);
    expect(clientsMade, 1);
    expect(github.closes, 1);

    // Once it has finished, the next fetch is a new request.
    github.respond = () async => githubResponse(200, json: releaseJson());
    await releases.fetchLatest();
    expect(github.requests, hasLength(2));
  });

  test('after a failure the next fetch is a new request', () async {
    github.respond = () async => throw const SocketException('offline');
    final releases = feed();
    await expectLater(
      releases.fetchLatest(),
      throwsA(isA<ReleaseFeedUnavailable>()),
    );
    github.respond = () async => githubResponse(200, json: releaseJson());
    expect((await releases.fetchLatest()).statusCode, 200);
    expect(github.requests, hasLength(2));
  });

  test('the answer is passed on as received', () async {
    github.respond = () async => githubResponse(
      404,
      json: {'message': 'Not Found'},
      headers: {'x-ratelimit-remaining': '57'},
    );
    final response = await feed().fetchLatest();
    expect(response.statusCode, 404);
    expect(response.contentType, 'application/json; charset=utf-8');
    expect(response.headers['x-ratelimit-remaining'], '57');
    expect(jsonDecode(utf8.decode(response.body)), {'message': 'Not Found'});
  });

  test('a redirect is returned, never followed', () async {
    github.respond = () async => githubResponse(
      302,
      headers: {'location': 'https://evil.example/latest'},
    );
    final response = await feed().fetchLatest();
    expect(response.statusCode, 302);
    expect(github.requests, hasLength(1));
  });

  group('size limit', () {
    test('a declared length over the limit is refused unread', () async {
      github.respond = () async => http.StreamedResponse(
        Stream.value(utf8.encode('{}')),
        200,
        contentLength: 256 * 1024 + 1,
      );
      await expectLater(
        feed().fetchLatest(),
        throwsA(isA<ReleaseFeedTooLarge>()),
      );
      expect(github.closes, 1);
    });

    test('an endless body is cut off at the limit', () async {
      var chunks = 0;
      Stream<List<int>> endless() async* {
        while (true) {
          chunks++;
          yield List.filled(1024, 0x20);
        }
      }

      github.respond = () async => http.StreamedResponse(endless(), 200);
      await expectLater(
        feed(maxBytes: 8 * 1024).fetchLatest(),
        throwsA(isA<ReleaseFeedTooLarge>()),
      );
      expect(chunks, lessThan(20));
      expect(github.closes, 1);
    });

    test('a body exactly at the limit is accepted', () async {
      github.respond = () async =>
          http.StreamedResponse(Stream.value(List.filled(4096, 0x20)), 200);
      final response = await feed(maxBytes: 4096).fetchLatest();
      expect(response.body, hasLength(4096));
    });

    test('an empty body is passed on (and later judged invalid)', () async {
      github.respond = () async => githubResponse(200, body: '');
      expect((await feed().fetchLatest()).body, isEmpty);
    });
  });

  group('no answer', () {
    test('no response in time: a timeout, and the client is closed', () async {
      github.hold();
      await expectLater(
        feed(timeout: const Duration(milliseconds: 50)).fetchLatest(),
        unavailable('timed out'),
      );
      expect(github.closes, 1);
    });

    test('a body that stalls also times out', () async {
      final stalled = StreamController<List<int>>();
      addTearDown(stalled.close);
      github.respond = () async => http.StreamedResponse(stalled.stream, 200);
      await expectLater(
        feed(timeout: const Duration(milliseconds: 50)).fetchLatest(),
        unavailable('timed out'),
      );
      expect(github.closes, 1);
    });

    test('offline, DNS and refused connections', () async {
      github.respond = () async =>
          throw const SocketException('Failed host lookup');
      await expectLater(feed().fetchLatest(), unavailable('SocketException'));
      github.respond = () async =>
          throw http.ClientException('Connection refused');
      await expectLater(feed().fetchLatest(), unavailable('ClientException'));
      github.respond = () async => throw const HttpException('reset');
      await expectLater(feed().fetchLatest(), unavailable('HttpException'));
      expect(github.closes, 3);
    });

    test('a TLS failure (e.g. an untrusted certificate)', () async {
      github.respond = () async =>
          throw const HandshakeException('CERTIFICATE_VERIFY_FAILED');
      await expectLater(feed().fetchLatest(), unavailable('TLS failure'));
      expect(github.closes, 1);
    });

    test('the reason never carries the error text', () async {
      github.respond = () async =>
          throw const SocketException('SYNTHETIC-DETAIL host 10.0.0.1');
      try {
        await feed().fetchLatest();
        fail('expected ReleaseFeedUnavailable');
      } on ReleaseFeedUnavailable catch (error) {
        expect('$error', isNot(contains('SYNTHETIC-DETAIL')));
        expect('$error', isNot(contains('10.0.0.1')));
      }
    });

    test('a defect is not disguised as a network failure', () async {
      github.respond = () async => throw StateError('bug');
      await expectLater(feed().fetchLatest(), throwsStateError);
      expect(github.closes, 1);
    });
  });

  test('defaults: 10 seconds in all, 256 KiB of metadata', () {
    final releases = GitHubReleaseFeed();
    expect(releases.timeout, const Duration(seconds: 10));
    expect(releases.maxBytes, 256 * 1024);
  });
}
