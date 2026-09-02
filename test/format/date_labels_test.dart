import 'package:flutter_test/flutter_test.dart';

import 'package:explore/format/date_labels.dart';

void main() {
  test('shortMonthDay renders "Mon D"', () {
    expect(shortMonthDay(DateTime(2026, 9, 2)), 'Sep 2');
    expect(shortMonthDay(DateTime(2026, 1, 15)), 'Jan 15');
    expect(shortMonthDay(DateTime(2026, 12, 31)), 'Dec 31');
  });

  group('relativeTimeLabel', () {
    final now = DateTime(2026, 9, 2, 12, 0, 0);

    test('under a minute → just now', () {
      expect(
        relativeTimeLabel(now.subtract(const Duration(seconds: 30)), now: now),
        'just now',
      );
    });

    test('future timestamps collapse to just now', () {
      expect(
        relativeTimeLabel(now.add(const Duration(minutes: 5)), now: now),
        'just now',
      );
    });

    test('minutes and hours pluralize', () {
      expect(
        relativeTimeLabel(now.subtract(const Duration(minutes: 1)), now: now),
        '1 minute ago',
      );
      expect(
        relativeTimeLabel(now.subtract(const Duration(minutes: 5)), now: now),
        '5 minutes ago',
      );
      expect(
        relativeTimeLabel(now.subtract(const Duration(hours: 3)), now: now),
        '3 hours ago',
      );
    });

    test('one day → Yesterday, then N days', () {
      expect(
        relativeTimeLabel(now.subtract(const Duration(days: 1)), now: now),
        'Yesterday',
      );
      expect(
        relativeTimeLabel(now.subtract(const Duration(days: 4)), now: now),
        '4 days ago',
      );
    });

    test('over a week → Mon D this year, Mon D, YYYY otherwise', () {
      expect(
        relativeTimeLabel(now.subtract(const Duration(days: 30)), now: now),
        'Aug 3',
      );
      expect(relativeTimeLabel(DateTime(2025, 6, 1), now: now), 'Jun 1, 2025');
    });
  });
}
