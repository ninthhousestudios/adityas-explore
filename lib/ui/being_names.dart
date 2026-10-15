import 'aditya_data.dart';
import 'being_slug.dart';
import 'popup_state.dart';

/// Link scheme for a being-name link in an assistant reply: `being:{slug}`.
const beingLinkScheme = 'being:';

/// Ambiguous-name marker slug for Vishvavasu when the reply alone doesn't say
/// which one it means; [resolveBeingLink] settles it at tap time.
const vishvavasuMarker = 'vishvavasu';

/// The 84-being table from the backend system prompt, one row per sign
/// (row index + 1 = sign, same order as [adityaSigns]). The model is told these
/// spellings, so the matcher matches them — not the card-title spellings, which
/// differ in places (adityas/ai/223 decisions).
const _beingTable = <List<String>>[
  // Aditya, Rishi, Gandharva, Rakshasa, Yaksha, Apsara, Naga
  [
    'Dhata',
    'Pulastya',
    'Tumburu',
    'Heti',
    'Rathakrit',
    'Kritasthali',
    'Vasuki',
  ],
  [
    'Aryama',
    'Pulaha',
    'Narada',
    'Praheti',
    'Rathauja',
    'Punjikasthali',
    'Kacchanira',
  ],
  ['Mitra', 'Atri', 'Haha', 'Paurusheya', 'Rathasvana', 'Menaka', 'Takshaka'],
  [
    'Varuna',
    'Vasishtha',
    'Huhu',
    'Chitrasvana',
    'Rathacitra',
    'Sahajanya',
    'Shukra',
  ],
  [
    'Indra',
    'Angiras',
    'Vishvavasu',
    'Varya',
    'Shrota',
    'Pramlocha',
    'Elapatra',
  ],
  [
    'Vivasvan',
    'Bhrigu',
    'Ugrasena',
    'Vyaghra',
    'Asarana',
    'Anumlocha',
    'Shankhapala',
  ],
  [
    'Tvashta',
    'Jamadagni',
    'Dhritarashtra',
    'Brahmapeta',
    'Shatajit',
    'Tilottama',
    'Kambala',
  ],
  [
    'Vishnu',
    'Vishvamitra',
    'Suryavarcas',
    'Makhapeta',
    'Satyajit',
    'Rambha',
    'Ashvatara',
  ],
  [
    'Amshu',
    'Kashyapa',
    'Ritasena',
    'Vidyucchatru',
    'Tarkshya',
    'Urvashi',
    'Mahashankha',
  ],
  ['Bhaga', 'Ayu', 'Urna', 'Sphurja', 'Arishtanemi', 'Purvacitti', 'Karkotaka'],
  ['Pusha', 'Gautama', 'Suruci', 'Vata', 'Sushena', 'Ghritachi', 'Dhananjaya'],
  [
    'Parjanya',
    'Bharadvaja',
    'Vishvavasu',
    'Varca',
    'Senajit',
    'Vishvaci',
    'Airavata',
  ],
];

/// Column order of [_beingTable].
const _columnTypes = [
  'aditya',
  'rishi',
  'gandharva',
  'rakshasa',
  'yaksha',
  'apsara',
  'naga',
];

/// Name → catalog slug (`{aditya}-{type}`). Vishvavasu, the one name in two
/// cells (sign 5 and sign 12 gandharva), maps to [vishvavasuMarker].
final Map<String, String> _slugForName = () {
  final map = <String, String>{};
  for (var row = 0; row < _beingTable.length; row++) {
    final aditya = _beingTable[row][0].toLowerCase();
    for (var col = 0; col < _columnTypes.length; col++) {
      final name = _beingTable[row][col];
      map[name] = map.containsKey(name)
          ? vishvavasuMarker
          : '$aditya-${_columnTypes[col]}';
    }
  }
  return map;
}();

/// Whole-word, case-sensitive alternation of every name, longest first so a
/// name that prefixes another can't shadow it.
final RegExp _namePattern = () {
  final names = _slugForName.keys.toList()
    ..sort((a, b) => b.length.compareTo(a.length));
  return RegExp('(?<![A-Za-z0-9_])(?:${names.join('|')})(?![A-Za-z0-9_])');
}();

/// Regions the rewrite must leave alone: fenced code blocks, inline code,
/// markdown links/images (label and URL), angle-bracket autolinks, bare URLs.
final RegExp _protected = RegExp(
  r'^[ \t]*(```|~~~)[\s\S]*?(^[ \t]*\1[^\n]*$|(?![\s\S]))' // fence (or to EOF)
  r'|(`+)[\s\S]*?\3' // inline code
  r'|!?\[[^\]\n]*\]\([^\s)]*\)' // link / image
  r'|<[a-zA-Z][a-zA-Z0-9+.-]*:[^\s>]*>' // autolink
  r'|https?://\S+', // bare URL
  multiLine: true,
);

final RegExp _indra = RegExp(r'(?<![A-Za-z0-9_])Indra(?![A-Za-z0-9_])');
final RegExp _parjanya = RegExp(r'(?<![A-Za-z0-9_])Parjanya(?![A-Za-z0-9_])');

/// Rewrite every capitalised whole-word being name in [markdown] to a
/// `[Name](being:{slug})` link, outside code and existing links.
///
/// Vishvavasu gets a concrete slug when the reply names exactly one of its two
/// Adityas (Indra / Parjanya) — the model's own text settles it; otherwise it
/// gets [vishvavasuMarker] for [resolveBeingLink] to settle against the chart.
String linkBeingNames(String markdown) {
  final hasIndra = _indra.hasMatch(markdown);
  final hasParjanya = _parjanya.hasMatch(markdown);
  final vishvavasuSlug = hasIndra == hasParjanya
      ? vishvavasuMarker
      : hasIndra
      ? 'indra-gandharva'
      : 'parjanya-gandharva';

  String linkSegment(String text) => text.replaceAllMapped(_namePattern, (m) {
    final name = m[0] ?? '';
    final slug = _slugForName[name];
    if (slug == null) return name;
    final target = slug == vishvavasuMarker ? vishvavasuSlug : slug;
    return '[$name]($beingLinkScheme$target)';
  });

  final out = StringBuffer();
  var last = 0;
  for (final m in _protected.allMatches(markdown)) {
    out
      ..write(linkSegment(markdown.substring(last, m.start)))
      ..write(markdown.substring(m.start, m.end));
    last = m.end;
  }
  out.write(linkSegment(markdown.substring(last)));
  return out.toString();
}

/// Resolve a `being:` link slug to the being to open. A concrete slug resolves
/// via [resolveBeingSlug]. [vishvavasuMarker] resolves to whichever of the
/// sign 5 / sign 12 gandharva [isPlaced] (a displayed planet in the open chart
/// activates it) if exactly one is, else to sign 5 (Indra) — adityas/ai/223.
BeingRef? resolveBeingLink(String slug, bool Function(BeingRef) isPlaced) {
  if (slug != vishvavasuMarker) return resolveBeingSlug(slug);
  final indra = resolveBeingSlug('indra-gandharva');
  final parjanya = resolveBeingSlug('parjanya-gandharva');
  if (indra == null || parjanya == null) return indra ?? parjanya;
  if (isPlaced(parjanya) && !isPlaced(indra)) return parjanya;
  return indra;
}
