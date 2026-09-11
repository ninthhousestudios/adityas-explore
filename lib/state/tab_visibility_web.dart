import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// Web implementation of [onTabVisible]: fires [onVisible] whenever the document
/// transitions back to `visible` (the user switches back to this tab). The
/// returned closure removes the listener — pass the same [web.EventListener]
/// reference to `removeEventListener`, so it is captured once here.
///
/// adityas/ai/85: a buyer who completes checkout for Solar Prism in a new tab
/// and returns to Explore should see the gate resolve without reloading, so the
/// app invalidates the entitlement fetch on this signal.
void Function() onTabVisible(void Function() onVisible) {
  final listener = ((web.Event _) {
    if (web.document.visibilityState == 'visible') onVisible();
  }).toJS;
  web.document.addEventListener('visibilitychange', listener);
  return () => web.document.removeEventListener('visibilitychange', listener);
}
