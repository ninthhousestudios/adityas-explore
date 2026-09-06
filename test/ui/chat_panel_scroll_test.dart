import 'package:flutter_test/flutter_test.dart';

import 'package:explore/ui/chat_panel.dart';

/// Sticky auto-scroll boundary tests (adityas/ai/29).
///
/// [nearBottom] is the load-bearing decision behind sticky auto-scroll: it
/// decides whether streamed tokens keep the view pinned to the end or leave the
/// user where they scrolled back to. These cover the threshold edges — inside
/// the band sticks, at/beyond it releases — and the overshoot case the band
/// exists for.
void main() {
  test('exactly at the bottom sticks', () {
    // pixels == maxScrollExtent → 0 < 80.
    expect(nearBottom(1000, 1000), isTrue);
  });

  test('just inside the band sticks', () {
    // 1000 - 921 = 79 < 80.
    expect(nearBottom(1000, 921), isTrue);
  });

  test('exactly at the threshold releases (strict less-than)', () {
    // 1000 - 920 = 80, not < 80.
    expect(nearBottom(1000, 920), isFalse);
  });

  test('scrolled well up to read back releases', () {
    expect(nearBottom(1000, 200), isFalse);
  });

  test('overshooting the extent still counts as stuck', () {
    // A stream can settle maxScrollExtent a frame behind the content, leaving
    // pixels a hair past it; the band keeps that pinned rather than releasing.
    expect(nearBottom(1000, 1002), isTrue);
  });

  test('threshold constant is the band width', () {
    expect(kStickToBottomThreshold, 80);
  });
}
