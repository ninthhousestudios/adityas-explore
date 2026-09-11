/// Registers [onVisible] to fire whenever the tab/window returns to the
/// foreground. Used to refetch entitlement after a purchase or renewal that
/// completed in another tab (adityas/ai/85): the buyer switches back to Explore
/// and the gate resolves on its own, no manual reload.
///
/// Web-only behaviour lives in `tab_visibility_web.dart` (conditional import).
/// The native build has no tab visibility model, so this stub is a no-op that
/// returns a no-op disposer.
void Function() onTabVisible(void Function() onVisible) => () {};
