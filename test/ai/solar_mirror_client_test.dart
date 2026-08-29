import 'dart:convert';

import 'package:charts_dart/charts_dart.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:explore/ai/solar_mirror_client.dart';

/// The open chart's birth data must ride along with a turn as the backend's
/// `ChartInput` shape (adityas/explore/50 ↔ adityas/ai/35): nested under `chart`,
/// with flat `lat`/`lon` and `YYYY-MM-DD` / `HH:MM:SS` civil date/time. A
/// chart-less turn (null chart) sends message only.
void main() {
  ChartData chart() => ChartData(
    name: 'Test',
    // DateTime.utc keeps the civil wall clock intact (see explore CLAUDE.md).
    dateTime: DateTime.utc(1990, 1, 15, 14, 30),
    birthLocation: GeoLocation(city: 'NYC', latitude: 40.7, longitude: -74.0),
    utcOffsetHours: -5.0,
    dstOffsetHours: 1.0,
  );

  /// A client whose POST handler captures the decoded request body into [sink]
  /// and answers `202 { turn_id }`.
  SolarMirrorClient clientCapturing(List<Map<String, dynamic>> sink) {
    final mock = MockClient((request) async {
      sink.add(jsonDecode(request.body) as Map<String, dynamic>);
      return http.Response(jsonEncode({'turn_id': 't1'}), 202);
    });
    return SolarMirrorClient(
      tokenProvider: ({forceRefresh = false}) async => 'jwt',
      httpClient: mock,
    );
  }

  test(
    'createTurn nests the open chart as the backend ChartInput shape',
    () async {
      final bodies = <Map<String, dynamic>>[];
      final id = await clientCapturing(
        bodies,
      ).createTurn(conversationId: 'c1', message: 'hi', chart: chart());

      expect(id, 't1');
      expect(bodies, hasLength(1));
      expect(bodies.single['message'], 'hi');
      expect(bodies.single['chart'], {
        'date': '1990-01-15',
        'time': '14:30:00',
        'lat': 40.7,
        'lon': -74.0,
        'utc_offset': -5.0,
        'dst_offset': 1.0,
      });
    },
  );

  test('createTurn omits chart when none is open', () async {
    final bodies = <Map<String, dynamic>>[];
    await clientCapturing(
      bodies,
    ).createTurn(conversationId: 'c1', message: 'hi');

    expect(bodies.single.containsKey('chart'), isFalse);
    expect(bodies.single, {'message': 'hi'});
  });

  test('chatPathPrefix routes durable accounts vs preview accounts', () {
    // josh@ninthhouse.studio → durable lane; every other allowlisted account
    // (and any non-allowlisted id) → preview lane.
    expect(chatPathPrefix('01214259-228c-46a9-bb3d-e229c8c4cb3f'), '/v1/ai');
    expect(
      chatPathPrefix('be96b3d3-5c64-40d2-ae77-73d6883d14a2'), // Laura
      '/v1/ai/preview',
    );
    expect(chatPathPrefix('someone-else'), '/v1/ai/preview');
    // The durable lane is a subset of chat access — its members can chat.
    expect(chatAllowlist.containsAll(durableChatAllowlist), isTrue);
  });

  test('createTurn posts to the configured lane base path', () async {
    final urls = <String>[];
    final mock = MockClient((request) async {
      urls.add(request.url.toString());
      return http.Response(jsonEncode({'turn_id': 't1'}), 202);
    });
    final client = SolarMirrorClient(
      tokenProvider: ({forceRefresh = false}) async => 'jwt',
      basePath: '/v1/ai',
      httpClient: mock,
    );

    await client.createTurn(conversationId: 'c1', message: 'hi');

    expect(urls.single, endsWith('/v1/ai/conversations/c1/turns'));
    expect(urls.single, isNot(contains('/preview/')));
  });
}
