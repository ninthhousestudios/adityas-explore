import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:explore/state/overlay.dart';
import 'package:explore/ui/popup_state.dart';

/// Locks the semantics the overlay lift (explore/45) had to preserve verbatim
/// when the popup stack moved out of `_ChartWheelState` into a shared provider:
/// the rect lifecycle (open/close reset, push/pop preserve) and the immutability
/// of the published stack. These used to be enforced by widget `setState`; now
/// the notifier is the only mutation path, so they need pinning against drift.
void main() {
  ProviderContainer container() {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    return c;
  }

  const area = 1000.0;
  // A stand-in popup that needs no chart layout to construct.
  PopupState popup([String planet = 'Sun']) => PlanetPopup(planet);

  group('OverlayController lifecycle', () {
    test('open puts a single popup on top and resets the rect', () {
      final c = container();
      // Give the window a non-default rect first, to prove open clears it.
      final overlay = c.read(overlayControllerProvider.notifier)
        ..open(popup())
        ..drag(const Offset(40, 40), area, area);
      expect(c.read(overlayControllerProvider).rect, isNotNull);

      overlay.open(popup('Moon'));
      final state = c.read(overlayControllerProvider);
      expect(state.depth, 1);
      expect(state.top, isA<PlanetPopup>());
      expect(state.rect, isNull, reason: 'a fresh root popup recenters');
    });

    test('push grows the stack and preserves the window rect', () {
      final c = container();
      final overlay = c.read(overlayControllerProvider.notifier)
        ..open(popup())
        ..drag(const Offset(40, 40), area, area);
      final moved = c.read(overlayControllerProvider).rect;
      expect(moved, isNotNull);

      overlay.push(popup('Mars'));
      final state = c.read(overlayControllerProvider);
      expect(state.depth, 2);
      expect(state.rect, moved, reason: 'drill-down keeps the window put');
    });

    test(
      'pop shrinks the stack, preserves the rect, and no-ops when empty',
      () {
        final c = container();
        final overlay = c.read(overlayControllerProvider.notifier)
          ..open(popup())
          ..push(popup('Mars'))
          ..drag(const Offset(40, 40), area, area);
        final moved = c.read(overlayControllerProvider).rect;

        overlay.pop();
        var state = c.read(overlayControllerProvider);
        expect(state.depth, 1);
        expect(state.rect, moved, reason: 'going back keeps the window put');

        overlay.pop();
        expect(c.read(overlayControllerProvider).isEmpty, isTrue);

        // Popping an empty stack is a no-op, not an error.
        overlay.pop();
        state = c.read(overlayControllerProvider);
        expect(state.isEmpty, isTrue);
      },
    );

    test('close empties the stack and resets the rect', () {
      final c = container();
      c.read(overlayControllerProvider.notifier)
        ..open(popup())
        ..drag(const Offset(40, 40), area, area)
        ..close();

      final state = c.read(overlayControllerProvider);
      expect(state.isEmpty, isTrue);
      expect(state.top, isNull);
      expect(state.rect, isNull);
    });

    test('showBeing opens a BeingFromName popup context-free', () {
      final c = container();
      const being = (name: 'Surya', type: 'Aditya', planet: 'Sun', sign: 0);

      c.read(overlayControllerProvider.notifier).showBeing(being);

      final top = c.read(overlayControllerProvider).top;
      expect(top, isA<BeingFromName>());
      expect((top as BeingFromName).being, being);
    });
  });

  group('OverlayLayer immutability', () {
    test('the published stack cannot be mutated in place', () {
      final c = container();
      c.read(overlayControllerProvider.notifier)
        ..open(popup())
        ..push(popup('Mars'));

      final stack = c.read(overlayControllerProvider).stack;
      expect(() => stack.add(YourBeingsPopup()), throwsUnsupportedError);
      expect(() => stack.removeLast(), throwsUnsupportedError);
    });
  });
}
