import 'package:flutter_test/flutter_test.dart';

import 'package:explore/state/conversation.dart';
import 'package:explore/ui/chat_panel.dart';

/// Placement tests for the compaction-seam divider (adityas/ai/121, /133).
///
/// [compactionSeamIndex] is the load-bearing logic: it decides where — and
/// whether — the "earlier messages condensed" divider is drawn. These cover the
/// boundary the algorithm turns on (strictly-after the watermark), the index-0
/// fail-safe (/133), and every null/absent branch.
void main() {
  final watermark = DateTime.utc(2026, 9, 2, 9, 0, 0);

  ChatMessage msg(String id, DateTime? createdAt) => ChatMessage(
    id: id,
    parentId: null,
    role: MessageRole.user,
    text: id,
    createdAt: createdAt,
  );

  test('divider sits above the first message strictly after the watermark', () {
    final messages = [
      msg('a', DateTime.utc(2026, 9, 2, 8, 0, 0)), // before
      msg('b', DateTime.utc(2026, 9, 2, 9, 0, 0)), // == watermark → still above
      msg('c', DateTime.utc(2026, 9, 2, 9, 30, 0)), // after → seam here
    ];
    expect(compactionSeamIndex(messages, watermark), 2);
  });

  test('a message whose createdAt == watermark is part of the condensed set '
      '(not the seam boundary)', () {
    final messages = [
      msg('a', DateTime.utc(2026, 9, 2, 9, 0, 0)), // == watermark
      msg('b', DateTime.utc(2026, 9, 2, 9, 0, 1)), // just after → seam here
    ];
    expect(compactionSeamIndex(messages, watermark), 1);
  });

  test('one microsecond before the watermark stays above the seam', () {
    final messages = [
      msg('a', watermark.subtract(const Duration(microseconds: 1))),
      msg('b', watermark.add(const Duration(microseconds: 1))),
    ];
    expect(compactionSeamIndex(messages, watermark), 1);
  });

  test('index 0: when the first message already post-dates the watermark the '
      'divider renders at the top, not suppressed (adityas/ai/133)', () {
    final messages = [
      msg('a', DateTime.utc(2026, 9, 2, 9, 30, 0)), // first, already after
      msg('b', DateTime.utc(2026, 9, 2, 10, 0, 0)),
    ];
    expect(compactionSeamIndex(messages, watermark), 0);
  });

  test('null watermark → no divider', () {
    final messages = [msg('a', DateTime.utc(2026, 9, 2, 9, 30, 0))];
    expect(compactionSeamIndex(messages, null), isNull);
  });

  test('no message post-dates the watermark → no divider', () {
    final messages = [
      msg('a', DateTime.utc(2026, 9, 2, 8, 0, 0)),
      msg('b', DateTime.utc(2026, 9, 2, 9, 0, 0)), // == watermark, not after
    ];
    expect(compactionSeamIndex(messages, watermark), isNull);
  });

  test(
    'null createdAt (live-appended) never matches — lands below the seam',
    () {
      final messages = [
        msg('resumed-before', DateTime.utc(2026, 9, 2, 8, 0, 0)),
        msg('resumed-after', DateTime.utc(2026, 9, 2, 9, 30, 0)), // seam here
        msg('live', null), // appended after resume, no server time
      ];
      expect(compactionSeamIndex(messages, watermark), 1);
    },
  );

  test('all null createdAt with a watermark → no divider', () {
    final messages = [msg('a', null), msg('b', null)];
    expect(compactionSeamIndex(messages, watermark), isNull);
  });

  test('empty transcript → no divider', () {
    expect(compactionSeamIndex(const [], watermark), isNull);
  });
}
