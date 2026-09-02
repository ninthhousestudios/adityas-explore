import 'aditya_data.dart';
import 'being_content.dart' show adityaName;
import 'popup_state.dart';

/// The seven being types under each Aditya — the valid `{type}` suffix of a
/// catalog slug. A slug whose suffix is not one of these resolves to null so the
/// chat dispatch degrades to a no-op instead of opening an empty popup.
const _beingTypes = <String>{
  'aditya',
  'rishi',
  'yaksha',
  'rakshasa',
  'gandharva',
  'apsara',
  'naga',
};

/// Aditya name (lowercase) → sign number, the inverse of [adityaSigns]. Built
/// once; the backend slug's first segment is an Aditya name.
final _signForAditya = <String, int>{
  for (final e in adityaSigns.entries) e.value.name.toLowerCase(): e.key,
};

/// Resolve a backend catalog slug (`{aditya}-{type}`, e.g. `varuna-rishi`,
/// `aryama-aditya`) to a [BeingRef] the overlay seam can open.
///
/// A being is uniquely `(sign, type)` client-side; the slug's two segments map
/// straight onto them (Aditya name → sign, suffix → type). The display `name`
/// is async content loaded per `(sign, type)` — left empty here for a companion
/// being (the overlay fills it from loaded content), set to the Aditya's own
/// name for the `aditya` being, whose name is available synchronously. `planet`
/// is empty: a chat-named being is not tied to a chart placement.
///
/// Returns null for an unrecognized Aditya, an unknown type, or an ill-formed
/// slug — the caller degrades to a no-op rather than navigating arbitrarily.
BeingRef? resolveBeingSlug(String slug) {
  final dash = slug.lastIndexOf('-');
  if (dash <= 0 || dash == slug.length - 1) return null;

  final adityaPart = slug.substring(0, dash).toLowerCase();
  final type = slug.substring(dash + 1).toLowerCase();

  final sign = _signForAditya[adityaPart];
  if (sign == null || !_beingTypes.contains(type)) return null;

  final name = type == 'aditya' ? (adityaName(sign) ?? '') : '';
  return (name: name, type: type, planet: '', sign: sign);
}
