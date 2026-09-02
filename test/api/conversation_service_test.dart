import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:explore/api/conversation_service.dart';

Future<String?> _token({bool forceRefresh = false}) async => 'jwt';

ConversationService _service(MockClient client) =>
    ConversationService(tokenProvider: _token, client: client);

void main() {
  test('list parses rows, cursor, and null titles', () async {
    late http.Request seen;
    final service = _service(
      MockClient((request) async {
        seen = request;
        return http.Response(
          jsonEncode({
            'conversations': [
              {
                'id': 'c1',
                'title': 'Mitra · Sep 2',
                'updated_at': '2026-09-02T10:00:00Z',
                'turn_count': 3,
              },
              {
                'id': 'c2',
                'title': null,
                'updated_at': '2026-09-01T10:00:00Z',
                'turn_count': 1,
              },
            ],
            'next_cursor': 'opaque-cursor',
          }),
          200,
        );
      }),
    );

    final page = await service.list(limit: 20);

    expect(seen.method, 'GET');
    expect(seen.url.path, '/v1/ai/conversations');
    expect(seen.url.queryParameters['limit'], '20');
    expect(seen.headers['Authorization'], 'Bearer jwt');
    expect(page.nextCursor, 'opaque-cursor');
    expect(page.conversations, hasLength(2));
    expect(page.conversations.first.id, 'c1');
    expect(page.conversations.first.title, 'Mitra · Sep 2');
    expect(page.conversations.first.turnCount, 3);
    expect(page.conversations[1].title, isNull);
  });

  test('list forwards the cursor when paginating', () async {
    late http.Request seen;
    final service = _service(
      MockClient((request) async {
        seen = request;
        return http.Response(
          jsonEncode({'conversations': <Object?>[], 'next_cursor': null}),
          200,
        );
      }),
    );

    final page = await service.list(cursor: 'page2');

    expect(seen.url.queryParameters['cursor'], 'page2');
    expect(page.nextCursor, isNull);
    expect(page.conversations, isEmpty);
  });

  test('fetch decodes the transcript with role → fromUser', () async {
    final service = _service(
      MockClient((request) async {
        expect(request.url.path, '/v1/ai/conversations/c1');
        return http.Response(
          jsonEncode({
            'id': 'c1',
            'title': 'Mitra · Sep 2',
            'mode': 'open',
            'created_at': '2026-09-02T09:00:00Z',
            'updated_at': '2026-09-02T10:00:00Z',
            'messages': [
              {
                'id': 'm1',
                'turn_id': 't1',
                'role': 'user',
                'content': 'what is my Soul Stance?',
                'created_at': '2026-09-02T09:00:00Z',
              },
              {
                'id': 'm2',
                'turn_id': 't1',
                'role': 'assistant',
                'content': 'Your Sun sits with the Adityas…',
                'created_at': '2026-09-02T09:00:01Z',
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );

    final history = await service.fetch('c1');

    expect(history.id, 'c1');
    expect(history.title, 'Mitra · Sep 2');
    expect(history.messages, hasLength(2));
    expect(history.messages.first.fromUser, isTrue);
    expect(history.messages.first.content, 'what is my Soul Stance?');
    expect(history.messages.last.fromUser, isFalse);
  });

  test('rename PATCHes the title and accepts 204', () async {
    late http.Request seen;
    final service = _service(
      MockClient((request) async {
        seen = request;
        return http.Response('', 204);
      }),
    );

    await service.rename('c1', 'My renamed thread');

    expect(seen.method, 'PATCH');
    expect(seen.url.path, '/v1/ai/conversations/c1');
    expect(jsonDecode(seen.body), {'title': 'My renamed thread'});
  });

  test('delete DELETEs and accepts 204', () async {
    late http.Request seen;
    final service = _service(
      MockClient((request) async {
        seen = request;
        return http.Response('', 204);
      }),
    );

    await service.delete('c1');

    expect(seen.method, 'DELETE');
    expect(seen.url.path, '/v1/ai/conversations/c1');
  });

  test('exportPdf returns the body bytes', () async {
    final pdf = [0x25, 0x50, 0x44, 0x46]; // %PDF
    final service = _service(
      MockClient((request) async {
        expect(request.url.path, '/v1/ai/conversations/c1/export.pdf');
        expect(request.headers['Accept'], 'application/pdf');
        return http.Response.bytes(pdf, 200);
      }),
    );

    final bytes = await service.exportPdf('c1');

    expect(bytes, pdf);
  });

  test('a non-2xx surfaces the backend error message', () async {
    final service = _service(
      MockClient(
        (_) async => http.Response(jsonEncode({'error': 'not found'}), 404),
      ),
    );

    expect(
      () => service.fetch('missing'),
      throwsA(
        isA<ConversationApiException>()
            .having((e) => e.statusCode, 'statusCode', 404)
            .having((e) => e.message, 'message', 'not found'),
      ),
    );
  });

  test('a 401 force-refreshes the token once and retries', () async {
    var calls = 0;
    var refreshed = false;
    Future<String?> token({bool forceRefresh = false}) async {
      if (forceRefresh) refreshed = true;
      return 'jwt';
    }

    final service = ConversationService(
      tokenProvider: token,
      client: MockClient((request) async {
        calls++;
        if (calls == 1) return http.Response('', 401);
        return http.Response(
          jsonEncode({'conversations': <Object?>[], 'next_cursor': null}),
          200,
        );
      }),
    );

    await service.list();

    expect(calls, 2);
    expect(refreshed, isTrue);
  });
}
