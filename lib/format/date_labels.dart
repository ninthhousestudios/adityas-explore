/// Small, dependency-free date/time labels for the UI (no `intl`).
///
/// Shared by the state layer (conversation-title composition), the chat wire
/// (the `{chart · date}` label minted at conversation creation), and the
/// conversations picker (relative "last active" line). Kept in a neutral
/// `format/` layer so none of those has to import another's package.
library;

const _shortMonths = <String>[
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// A compact `Mon D` label, e.g. `Sep 2`. Used in the deterministic
/// conversation title (`{chart-name snapshot} · {date}`, adityas/ai/64).
String shortMonthDay(DateTime dt) {
  final local = dt.toLocal();
  return '${_shortMonths[local.month - 1]} ${local.day}';
}

/// A coarse "time ago" label for the picker's secondary line, e.g. `just now`,
/// `5 minutes ago`, `3 hours ago`, `Yesterday`, `4 days ago`, or a `Mon D`
/// (this year) / `Mon D, YYYY` (older) fallback once it is more than a week old.
///
/// [now] is injectable so callers/tests are deterministic; it defaults to the
/// wall clock. Future timestamps (clock skew) collapse to `just now`.
String relativeTimeLabel(DateTime when, {DateTime? now}) {
  final ref = now ?? DateTime.now();
  final delta = ref.difference(when);

  if (delta.inSeconds < 60) return 'just now';
  if (delta.inMinutes < 60) return _plural(delta.inMinutes, 'minute');
  if (delta.inHours < 24) return _plural(delta.inHours, 'hour');
  if (delta.inDays == 1) return 'Yesterday';
  if (delta.inDays < 7) return _plural(delta.inDays, 'day');

  final local = when.toLocal();
  final monthDay = shortMonthDay(when);
  return local.year == ref.toLocal().year
      ? monthDay
      : '$monthDay, ${local.year}';
}

String _plural(int n, String unit) => '$n $unit${n == 1 ? '' : 's'} ago';
