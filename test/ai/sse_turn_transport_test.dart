import 'dart:async';
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

/// Yield to the microtask/event queue until [cond] holds (or a bounded number
/// of turns elapse) — lets a test observe a pending await inside `start()`.
Future<void> _pumpUntil(bool Function() cond) async {
  for (var i = 0; i < 1000 && !cond(); i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

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

    // ── Atomic rotation (adityas/ai/91) ──────────────────────────────
    // start() is an async* generator with awaits before its first yield;
    // adopt/reset fired mid-open must win, and the abandoned open must not
    // write conversation/turn state. Cancelling the subscription cannot
    // preempt the pre-yield body — the epoch guard is what makes it atomic.

    test('resetConversation during the create POST abandons the opening turn '
        '(New Chat mid-connect does not clobber the reset)', () async {
      final gate = Completer<void>();
      var conversationPosts = 0;
      var turnPosts = 0;
      final mock = MockClient((request) async {
        if (request.url.path.endsWith('/conversations')) {
          conversationPosts++;
          await gate.future; // hold the mint open across the rotation
          return http.Response(jsonEncode({'conversation_id': 'c1'}), 201);
        }
        turnPosts++;
        return http.Response(jsonEncode({'turn_id': 't1'}), 202);
      });
      final transport = SseTurnTransport(
        tokenProvider: ({forceRefresh = false}) async => 'jwt',
        baseUrl: 'https://api.test',
        httpClient: mock,
        byteSource: _FakeByteSource(_happyStream).call,
      );

      final events = transport.start(const TurnRequest(text: 'hi')).toList();
      await _pumpUntil(() => conversationPosts == 1); // POST now in flight
      transport.resetConversation(); // New Chat mid-connect
      gate.complete();
      final emitted = await events;

      expect(emitted, isEmpty); // opening turn abandoned, nothing streamed
      expect(turnPosts, 0); // no turn landed in the reset-away conversation
      expect(transport.conversationId, isNull); // the reset stuck
    });

    test(
      'adoptConversation during the create POST wins over the in-flight mint '
      '(Resume mid-connect)',
      () async {
        final gate = Completer<void>();
        var conversationPosts = 0;
        var turnPosts = 0;
        final mock = MockClient((request) async {
          if (request.url.path.endsWith('/conversations')) {
            conversationPosts++;
            await gate.future;
            return http.Response(
              jsonEncode({'conversation_id': 'minted'}),
              201,
            );
          }
          turnPosts++;
          return http.Response(jsonEncode({'turn_id': 't1'}), 202);
        });
        final transport = SseTurnTransport(
          tokenProvider: ({forceRefresh = false}) async => 'jwt',
          baseUrl: 'https://api.test',
          httpClient: mock,
          byteSource: _FakeByteSource(_happyStream).call,
        );

        final events = transport.start(const TurnRequest(text: 'hi')).toList();
        await _pumpUntil(() => conversationPosts == 1); // mint POST in flight
        transport.adoptConversation('resumed-2'); // Resume mid-connect
        gate.complete();
        final emitted = await events;

        expect(emitted, isEmpty); // the pre-adopt open was abandoned
        expect(turnPosts, 0); // it never posted a turn to 'minted'
        expect(transport.conversationId, 'resumed-2'); // adopt not clobbered
      },
    );

    test(
      'a 404 on an adopted conversation fails instead of silently re-minting',
      () async {
        var conversationPosts = 0;
        final mock = MockClient((request) async {
          if (request.url.path.endsWith('/conversations')) {
            conversationPosts++;
            return http.Response(jsonEncode({'conversation_id': 'fresh'}), 201);
          }
          return http.Response(jsonEncode({'error': 'gone'}), 404);
        });
        final transport = SseTurnTransport(
          tokenProvider: ({forceRefresh = false}) async => 'jwt',
          baseUrl: 'https://api.test',
          httpClient: mock,
          byteSource: _FakeByteSource(_happyStream).call,
        )..adoptConversation('resumed-1');

        await expectLater(
          transport.start(const TurnRequest(text: 'hi')).toList(),
          throwsA(isA<TurnTransportException>()),
        );
        // Never minted a new thread divorced from the resumed transcript.
        expect(conversationPosts, 0);
      },
    );

    test('conversationId exposes the active thread for the picker', () async {
      final mock = MockClient((request) async {
        if (request.url.path.endsWith('/conversations')) {
          return http.Response(
            jsonEncode({'conversation_id': 'minted-1'}),
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

      expect(transport.conversationId, isNull);
      await transport.start(const TurnRequest(text: 'hi')).toList();
      expect(transport.conversationId, 'minted-1'); // self-minted, tracked
      transport.adoptConversation('resumed-9');
      expect(transport.conversationId, 'resumed-9');
      transport.resetConversation();
      expect(transport.conversationId, isNull);
    });

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

  group('SseTurnTransport.cancel (adityas/ai/137)', () {
    // Drive a happy turn to completion so the transport holds a turn id, then
    // hand the caller the mock's recorded cancel request. Every case shares this
    // setup; only the cancel-route response differs.
    Future<http.Request?> startThenCancel(
      http.Response Function() cancelResponse,
    ) async {
      http.Request? cancelRequest;
      final mock = MockClient((request) async {
        if (request.url.path.endsWith('/conversations')) {
          return http.Response(jsonEncode({'conversation_id': 'c1'}), 201);
        }
        if (request.url.path.endsWith('/turns')) {
          return http.Response(jsonEncode({'turn_id': 't1'}), 202);
        }
        cancelRequest = request;
        return cancelResponse();
      });
      final transport = SseTurnTransport(
        tokenProvider: ({forceRefresh = false}) async => 'jwt',
        baseUrl: 'https://api.test',
        httpClient: mock,
        byteSource: _FakeByteSource(_happyStream).call,
      );
      await transport.start(const TurnRequest(text: 'hi')).toList();
      await transport.cancel();
      return cancelRequest;
    }

    // Like [startThenCancel] but returns cancel()'s own result — whether the
    // stop is in effect (adityas/ai/141).
    Future<bool> startThenCancelResult(
      http.Response Function() cancelResponse,
    ) async {
      final mock = MockClient((request) async {
        if (request.url.path.endsWith('/conversations')) {
          return http.Response(jsonEncode({'conversation_id': 'c1'}), 201);
        }
        if (request.url.path.endsWith('/turns')) {
          return http.Response(jsonEncode({'turn_id': 't1'}), 202);
        }
        return cancelResponse();
      });
      final transport = SseTurnTransport(
        tokenProvider: ({forceRefresh = false}) async => 'jwt',
        baseUrl: 'https://api.test',
        httpClient: mock,
        byteSource: _FakeByteSource(_happyStream).call,
      );
      await transport.start(const TurnRequest(text: 'hi')).toList();
      return transport.cancel();
    }

    test('POSTs the cancel route for the in-flight turn, bearer auth, no '
        'body; a 202 reports the stop in effect', () async {
      final request = await startThenCancel(() => http.Response('', 202));
      expect(request, isNotNull);
      expect(request!.method, 'POST');
      expect(request.url.path, '/v1/ai/turns/t1/cancel');
      expect(request.headers['authorization'], 'Bearer jwt');
      expect(request.body, isEmpty);
      // 202 acks the stop.
      expect(await startThenCancelResult(() => http.Response('', 202)), isTrue);
    });

    test('idempotent: a 404 (turn already finished/evicted/not ours) reports '
        'the stop in effect — nothing left to stop', () async {
      expect(await startThenCancelResult(() => http.Response('', 404)), isTrue);
    });

    test('a non-202/404 status reports the stop NOT in effect — the turn may '
        'still be generating (adityas/ai/141)', () async {
      // 500 and other statuses: the stop did not take. The caller keeps the open
      // stream visible instead of asserting a cancellation that never happened.
      expect(
        await startThenCancelResult(() => http.Response('nope', 500)),
        isFalse,
      );
      expect(
        await startThenCancelResult(() => http.Response('', 409)),
        isFalse,
      );
    });

    test(
      'a transport throw reports the stop NOT in effect (adityas/ai/141)',
      () async {
        expect(
          await startThenCancelResult(() => throw Exception('network down')),
          isFalse,
        );
      },
    );

    test('a Stop while still connecting reports the stop in effect (latched), '
        'with no POST yet (adityas/ai/140 + ai/141)', () async {
      final gate = Completer<void>();
      var turnPostsStarted = 0;
      final cancelPaths = <String>[];
      final mock = MockClient((request) async {
        if (request.url.path.endsWith('/conversations')) {
          return http.Response(jsonEncode({'conversation_id': 'c1'}), 201);
        }
        if (request.url.path.endsWith('/turns')) {
          turnPostsStarted++;
          await gate.future;
          return http.Response(jsonEncode({'turn_id': 't-late'}), 202);
        }
        cancelPaths.add(request.url.path);
        return http.Response('', 202);
      });
      final transport = SseTurnTransport(
        tokenProvider: ({forceRefresh = false}) async => 'jwt',
        baseUrl: 'https://api.test',
        httpClient: mock,
        byteSource: _FakeByteSource(_happyStream).call,
      );

      final events = transport.start(const TurnRequest(text: 'hi')).toList();
      await _pumpUntil(() => turnPostsStarted == 1);
      // Connecting: the id is unknown, so the stop is latched — reported in
      // effect (it will fire), not a failure, and nothing is POSTed yet.
      expect(await transport.cancel(), isTrue);
      expect(cancelPaths, isEmpty);
      gate.complete();
      await events;
      expect(cancelPaths.single, '/v1/ai/turns/t-late/cancel');
    });

    test('no-op before any turn has been started — no POST fired', () async {
      var posts = 0;
      final transport = SseTurnTransport(
        tokenProvider: ({forceRefresh = false}) async => 'jwt',
        baseUrl: 'https://api.test',
        httpClient: MockClient((_) async {
          posts++;
          return http.Response('', 202);
        }),
      );
      await transport.cancel();
      expect(posts, 0);
    });

    test('Stop during TurnConnecting latches, then cancels the exact turn once '
        'its id is minted (adityas/ai/140)', () async {
      final gate = Completer<void>();
      var turnPostsStarted = 0;
      final cancelPaths = <String>[];
      final mock = MockClient((request) async {
        if (request.url.path.endsWith('/conversations')) {
          return http.Response(jsonEncode({'conversation_id': 'c1'}), 201);
        }
        if (request.url.path.endsWith('/turns')) {
          turnPostsStarted++;
          await gate.future; // hold the turn open so Stop lands mid-connect
          return http.Response(jsonEncode({'turn_id': 't-late'}), 202);
        }
        cancelPaths.add(request.url.path);
        return http.Response('', 202);
      });
      final transport = SseTurnTransport(
        tokenProvider: ({forceRefresh = false}) async => 'jwt',
        baseUrl: 'https://api.test',
        httpClient: mock,
        byteSource: _FakeByteSource(_happyStream).call,
      );

      final events = transport.start(const TurnRequest(text: 'hi')).toList();
      await _pumpUntil(
        () => turnPostsStarted == 1,
      ); // turn POST in flight, no id
      await transport.cancel(); // Stop during TurnConnecting — latches intent
      expect(cancelPaths, isEmpty); // nothing to POST yet — id unknown
      gate.complete();
      final emitted = await events;

      // The exact minted id was cancelled — not a no-op that leaves it running.
      expect(cancelPaths.single, '/v1/ai/turns/t-late/cancel');
      // The stream still flowed so the terminal sequence reaches the notifier.
      expect(emitted.last, isA<DoneEvent>());
    });

    test('Stop during TurnConnecting targets the new turn, never the stale '
        'previous one (adityas/ai/140)', () async {
      final gate = Completer<void>();
      var turnPostsStarted = 0;
      var nextTurnId = 't1';
      final cancelPaths = <String>[];
      final mock = MockClient((request) async {
        if (request.url.path.endsWith('/conversations')) {
          return http.Response(jsonEncode({'conversation_id': 'c1'}), 201);
        }
        if (request.url.path.endsWith('/turns')) {
          turnPostsStarted++;
          if (turnPostsStarted == 2) {
            await gate.future; // hold the 2nd turn open across the Stop
          }
          return http.Response(jsonEncode({'turn_id': nextTurnId}), 202);
        }
        cancelPaths.add(request.url.path);
        return http.Response('', 202);
      });
      final transport = SseTurnTransport(
        tokenProvider: ({forceRefresh = false}) async => 'jwt',
        baseUrl: 'https://api.test',
        httpClient: mock,
        byteSource: _FakeByteSource(_happyStream).call,
      );

      // First turn completes → the transport now holds a stale id (t1).
      await transport.start(const TurnRequest(text: 'one')).toList();
      // Second turn: hold it mid-connect and hit Stop.
      nextTurnId = 't2';
      final events = transport.start(const TurnRequest(text: 'two')).toList();
      await _pumpUntil(() => turnPostsStarted == 2);
      await transport.cancel(); // must not target t1
      gate.complete();
      await events;

      expect(cancelPaths.single, '/v1/ai/turns/t2/cancel');
    });

    test('no-op when signed out — a null token fires no POST', () async {
      var cancelPosts = 0;
      final mock = MockClient((request) async {
        if (request.url.path.endsWith('/conversations')) {
          return http.Response(jsonEncode({'conversation_id': 'c1'}), 201);
        }
        if (request.url.path.endsWith('/turns')) {
          return http.Response(jsonEncode({'turn_id': 't1'}), 202);
        }
        cancelPosts++;
        return http.Response('', 202);
      });
      // Token present to open the turn, gone by the time the user hits Stop.
      String? token = 'jwt';
      final transport = SseTurnTransport(
        tokenProvider: ({forceRefresh = false}) async => token,
        baseUrl: 'https://api.test',
        httpClient: mock,
        byteSource: _FakeByteSource(_happyStream).call,
      );
      await transport.start(const TurnRequest(text: 'hi')).toList();
      token = null; // signed out
      await transport.cancel();
      expect(cancelPosts, 0);
    });
  });
}
