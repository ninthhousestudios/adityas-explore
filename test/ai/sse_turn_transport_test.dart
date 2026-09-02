import 'dart:convert';

import 'package:charts_dart/charts_dart.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:explore/ai/sse.dart';
import 'package:explore/ai/sse_turn_transport.dart';
import 'package:explore/state/turn_transport.dart';

/// A byte source that records every (uri, headers) it is asked for and replays a
/// scripted SSE body — the seam standing in for a real fetch/`dart:io` stream.
class _FakeByteSource {
  final List<Uri> uris = [];
  final List<Map<String, String>> headers = [];
  final String body;

  _FakeByteSource(this.body);

  Stream<List<int>> call(Uri uri, Map<String, String> h) async* {
    uris.add(uri);
    headers.add(h);
    // Chunk boundaries are the parser's problem, not ours: one lump is fine.
    yield utf8.encode(body);
  }
}

/// SSE for a clean two-delta turn ending in usage + done, ids 0..3.
const _happyStream =
    'event: delta\n'
    'id: 0\n'
    'data: {"text":"Hel"}\n'
    '\n'
    'event: delta\n'
    'id: 1\n'
    'data: {"text":"lo"}\n'
    '\n'
    'event: usage\n'
    'id: 2\n'
    'data: {"promptTokens":10,"outputTokens":5,"totalTokens":15}\n'
    '\n'
    'event: done\n'
    'id: 3\n'
    'data: {}\n'
    '\n';

void main() {
  group('decodeTurnFrame', () {
    test('maps each known durable event, carrying the id as the cursor', () {
      expect(
        decodeTurnFrame(const SseFrame('delta', '{"text":"hi"}', '7')),
        isA<DeltaEvent>()
            .having((e) => e.text, 'text', 'hi')
            .having((e) => e.eventId, 'eventId', '7'),
      );
      expect(
        decodeTurnFrame(
          const SseFrame(
            'usage',
            '{"promptTokens":3,"outputTokens":4,"totalTokens":7}',
            '8',
          ),
        ),
        isA<UsageEvent>()
            .having((e) => e.usage.inputTokens, 'input', 3)
            .having((e) => e.usage.outputTokens, 'output', 4)
            .having((e) => e.usage.totalTokens, 'total', 7),
      );
      expect(
        decodeTurnFrame(const SseFrame('error', '{"message":"boom"}', '9')),
        isA<ErrorEvent>().having((e) => e.message, 'message', 'boom'),
      );
      expect(
        decodeTurnFrame(const SseFrame('done', '{}', '10')),
        isA<DoneEvent>(),
      );
    });

    test('tool_start carries the tool name and its args (the being slug)', () {
      final event = decodeTurnFrame(
        const SseFrame(
          'tool_start',
          '{"name":"show_being","args":{"slug":"varuna-rishi"}}',
          '11',
        ),
      );
      expect(
        event,
        isA<ToolStartEvent>()
            .having((e) => e.tool, 'tool', 'show_being')
            .having((e) => e.args?['slug'], 'slug', 'varuna-rishi')
            .having((e) => e.eventId, 'eventId', '11'),
      );
    });

    test('tool_end carries the tool name (no args)', () {
      expect(
        decodeTurnFrame(
          const SseFrame('tool_end', '{"name":"show_being"}', '12'),
        ),
        isA<ToolEndEvent>().having((e) => e.tool, 'tool', 'show_being'),
      );
    });

    test(
      'an unrecognized event becomes UnknownEvent (ignored, cursor kept)',
      () {
        final event = decodeTurnFrame(const SseFrame('reasoning', '{}', '11'));
        expect(
          event,
          isA<UnknownEvent>()
              .having((e) => e.type, 'type', 'reasoning')
              .having((e) => e.eventId, 'eventId', '11'),
        );
      },
    );

    test('a frame without an id carries the empty cursor', () {
      expect(decodeTurnFrame(const SseFrame('done', '{}', null)).eventId, '');
    });
  });

  group('SseTurnTransport.start', () {
    test(
      'mints a conversation, posts the turn, then streams decoded events',
      () async {
        final posted = <Uri>[];
        final bodies = <Map<String, dynamic>>[];
        final mock = MockClient((request) async {
          posted.add(request.url);
          if (request.url.path.endsWith('/conversations')) {
            return http.Response(jsonEncode({'conversation_id': 'c1'}), 201);
          }
          bodies.add(jsonDecode(request.body) as Map<String, dynamic>);
          // The durable path requires an Idempotency-Key on the turn POST.
          expect(request.headers['idempotency-key'], isNotEmpty);
          return http.Response(jsonEncode({'turn_id': 't1'}), 202);
        });
        final source = _FakeByteSource(_happyStream);
        final transport = SseTurnTransport(
          tokenProvider: ({forceRefresh = false}) async => 'jwt',
          baseUrl: 'https://api.test',
          httpClient: mock,
          byteSource: source.call,
        );

        final events = await transport
            .start(const TurnRequest(text: 'hi'))
            .toList();

        // A chart-less TurnRequest sends message only.
        expect(bodies.single, {'message': 'hi'});
        // Conversation minted, then the turn posted under it.
        expect(posted[0].path, '/v1/ai/conversations');
        expect(posted[1].path, '/v1/ai/conversations/c1/turns');
        // Stream opened against the returned turn id.
        expect(source.uris.single.path, '/v1/ai/turns/t1/stream');

        expect(events.map((e) => e.runtimeType).toList(), [
          DeltaEvent,
          DeltaEvent,
          UsageEvent,
          DoneEvent,
        ]);
        final delta = events.first as DeltaEvent;
        expect(delta.text, 'Hel');
        expect(delta.eventId, '0');
        expect((events[2] as UsageEvent).usage.totalTokens, 15);
      },
    );

    test(
      'rides the open chart along as the backend ChartInput shape (ai/65)',
      () async {
        final bodies = <Map<String, dynamic>>[];
        final mock = MockClient((request) async {
          if (request.url.path.endsWith('/conversations')) {
            return http.Response(jsonEncode({'conversation_id': 'c1'}), 201);
          }
          bodies.add(jsonDecode(request.body) as Map<String, dynamic>);
          return http.Response(jsonEncode({'turn_id': 't1'}), 202);
        });
        final transport = SseTurnTransport(
          tokenProvider: ({forceRefresh = false}) async => 'jwt',
          baseUrl: 'https://api.test',
          httpClient: mock,
          byteSource: _FakeByteSource(_happyStream).call,
        );

        await transport
            .start(
              TurnRequest(
                text: 'hi',
                chart: ChartData(
                  name: 'Test',
                  // DateTime.utc keeps the civil wall clock intact.
                  dateTime: DateTime.utc(1990, 1, 15, 14, 30),
                  birthLocation: GeoLocation(
                    city: 'NYC',
                    latitude: 40.7,
                    longitude: -74.0,
                  ),
                  utcOffsetHours: -5.0,
                  dstOffsetHours: 1.0,
                ),
              ),
            )
            .toList();

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

    test(
      'caches the conversation across turns (one POST /conversations)',
      () async {
        var conversationPosts = 0;
        final mock = MockClient((request) async {
          if (request.url.path.endsWith('/conversations')) {
            conversationPosts++;
            return http.Response(jsonEncode({'conversation_id': 'c1'}), 201);
          }
          return http.Response(jsonEncode({'turn_id': 't1'}), 202);
        });
        final transport = SseTurnTransport(
          tokenProvider: ({forceRefresh = false}) async => 'jwt',
          baseUrl: 'https://api.test',
          httpClient: mock,
          byteSource: _FakeByteSource(_happyStream).call,
        );

        await transport.start(const TurnRequest(text: 'one')).toList();
        await transport.start(const TurnRequest(text: 'two')).toList();

        expect(conversationPosts, 1);
      },
    );

    test(
      'resetConversation forces a fresh conversation on the next turn',
      () async {
        var conversationPosts = 0;
        final mock = MockClient((request) async {
          if (request.url.path.endsWith('/conversations')) {
            conversationPosts++;
            return http.Response(
              jsonEncode({'conversation_id': 'c$conversationPosts'}),
              201,
            );
          }
          return http.Response(jsonEncode({'turn_id': 't1'}), 202);
        });
        final transport = SseTurnTransport(
          tokenProvider: ({forceRefresh = false}) async => 'jwt',
          baseUrl: 'https://api.test',
          httpClient: mock,
          byteSource: _FakeByteSource(_happyStream).call,
        );

        await transport.start(const TurnRequest(text: 'one')).toList();
        transport.resetConversation();
        await transport.start(const TurnRequest(text: 'two')).toList();

        expect(conversationPosts, 2);
      },
    );

    test('mints the conversation with the composed title', () async {
      Object? createBody;
      final mock = MockClient((request) async {
        if (request.url.path.endsWith('/conversations')) {
          createBody = request.body.isEmpty ? null : jsonDecode(request.body);
          return http.Response(jsonEncode({'conversation_id': 'c1'}), 201);
        }
        return http.Response(jsonEncode({'turn_id': 't1'}), 202);
      });
      final transport = SseTurnTransport(
        tokenProvider: ({forceRefresh = false}) async => 'jwt',
        baseUrl: 'https://api.test',
        httpClient: mock,
        byteSource: _FakeByteSource(_happyStream).call,
      );

      await transport
          .start(
            const TurnRequest(text: 'hi', conversationTitle: 'Mitra · Sep 2'),
          )
          .toList();

      expect(createBody, {'title': 'Mitra · Sep 2'});
    });

    test('adoptConversation appends to the given id without minting', () async {
      var conversationPosts = 0;
      final turnPaths = <String>[];
      final mock = MockClient((request) async {
        if (request.url.path.endsWith('/conversations')) {
          conversationPosts++;
          return http.Response(jsonEncode({'conversation_id': 'fresh'}), 201);
        }
        turnPaths.add(request.url.path);
        return http.Response(jsonEncode({'turn_id': 't1'}), 202);
      });
      final transport = SseTurnTransport(
        tokenProvider: ({forceRefresh = false}) async => 'jwt',
        baseUrl: 'https://api.test',
        httpClient: mock,
        byteSource: _FakeByteSource(_happyStream).call,
      );

      final events = (transport..adoptConversation('resumed-1')).start(
        const TurnRequest(text: 'continue'),
      );
      await events.toList();

      expect(conversationPosts, 0); // no fresh mint — the resumed id is reused
      expect(turnPaths.single, '/v1/ai/conversations/resumed-1/turns');
    });

    test(
      'a 404 on the turn POST re-mints the conversation and retries',
      () async {
        final turnPosts = <String>[];
        var conversationPosts = 0;
        final mock = MockClient((request) async {
          if (request.url.path.endsWith('/conversations')) {
            conversationPosts++;
            return http.Response(
              jsonEncode({'conversation_id': 'c$conversationPosts'}),
              201,
            );
          }
          turnPosts.add(request.url.path);
          // The first (stale) conversation 404s; the re-minted one succeeds.
          if (request.url.path.contains('/c1/')) {
            return http.Response(jsonEncode({'error': 'not found'}), 404);
          }
          return http.Response(jsonEncode({'turn_id': 't1'}), 202);
        });
        final transport = SseTurnTransport(
          tokenProvider: ({forceRefresh = false}) async => 'jwt',
          baseUrl: 'https://api.test',
          httpClient: mock,
          byteSource: _FakeByteSource(_happyStream).call,
        );

        final events = await transport
            .start(const TurnRequest(text: 'hi'))
            .toList();

        expect(conversationPosts, 2); // stale c1, then fresh c2
        expect(turnPosts, [
          '/v1/ai/conversations/c1/turns',
          '/v1/ai/conversations/c2/turns',
        ]);
        expect(events.last, isA<DoneEvent>());
      },
    );

    test('a non-signed-in transport errors before any HTTP call', () async {
      final transport = SseTurnTransport(
        tokenProvider: ({forceRefresh = false}) async => null,
        baseUrl: 'https://api.test',
        httpClient: MockClient((_) async => http.Response('nope', 500)),
        byteSource: _FakeByteSource('').call,
      );

      expect(
        transport.start(const TurnRequest(text: 'hi')).toList(),
        throwsA(isA<TurnTransportException>()),
      );
    });
  });

  group('SseTurnTransport.resume', () {
    test('replays from the cursor via a Last-Event-ID header', () async {
      final mock = MockClient((request) async {
        if (request.url.path.endsWith('/conversations')) {
          return http.Response(jsonEncode({'conversation_id': 'c1'}), 201);
        }
        return http.Response(jsonEncode({'turn_id': 't1'}), 202);
      });
      final source = _FakeByteSource(_happyStream);
      final transport = SseTurnTransport(
        tokenProvider: ({forceRefresh = false}) async => 'jwt',
        baseUrl: 'https://api.test',
        httpClient: mock,
        byteSource: source.call,
      );

      // A started turn establishes the turn id resume re-attaches to.
      await transport.start(const TurnRequest(text: 'hi')).toList();
      await transport.resume('1').toList();

      // Second stream call is the resume, carrying the cursor; start carried none.
      expect(source.headers[0].containsKey('last-event-id'), isFalse);
      expect(source.headers[1]['last-event-id'], '1');
      expect(source.uris[1].path, '/v1/ai/turns/t1/stream');
    });

    test(
      'resume before any turn is a StateError-free transport error',
      () async {
        final transport = SseTurnTransport(
          tokenProvider: ({forceRefresh = false}) async => 'jwt',
          baseUrl: 'https://api.test',
          httpClient: MockClient((_) async => http.Response('{}', 200)),
          byteSource: _FakeByteSource('').call,
        );

        expect(
          transport.resume('0').toList(),
          throwsA(isA<TurnTransportException>()),
        );
      },
    );
  });
}
