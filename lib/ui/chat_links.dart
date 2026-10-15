import 'aditya_data.dart';
import 'being_slug.dart';
import 'popup_state.dart';

/// Link schemes for a linked name in an assistant reply (adityas/ai/223).
const beingLinkScheme = 'being:';
const beingTypeLinkScheme = 'being-type:';
const planetLinkScheme = 'planet:';

/// Ambiguous-name marker slug for Vishvavasu when the reply alone doesn't say
/// which one it means; [resolveBeingLink] settles it at tap time.
const vishvavasuMarker = 'vishvavasu';

/// A tapped name link, decoded from its URL by [parseChatLink].
sealed class ChatLink {
  const ChatLink();
}

/// One of the 84 beings, by catalog slug (or [vishvavasuMarker]).
class BeingLink extends ChatLink {
  const BeingLink(this.slug);
  final String slug;
}

/// One of the seven being types (`aditya`, `rishi`, …) — the type card.
class BeingTypeLink extends ChatLink {
  const BeingTypeLink(this.type);
  final String type;
}

/// One of the nine displayed planets (`sun` … `ketu`) — the planet card.
class PlanetLink extends ChatLink {
  const PlanetLink(this.body);
  final String body;
}

/// Decode a link URL emitted by [linkChatNames]; null for any other URL.
ChatLink? parseChatLink(String url) {
  if (url.startsWith(beingTypeLinkScheme)) {
    final type = url.substring(beingTypeLinkScheme.length);
    return _columnTypes.contains(type) ? BeingTypeLink(type) : null;
  }
  if (url.startsWith(beingLinkScheme)) {
    return BeingLink(url.substring(beingLinkScheme.length));
  }
  if (url.startsWith(planetLinkScheme)) {
    final body = url.substring(planetLinkScheme.length);
    return defaultGrahas.contains(body) ? PlanetLink(body) : null;
  }
  return null;
}

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

/// Column order of [_beingTable] — also the seven being-type keys.
const _columnTypes = [
  'aditya',
  'rishi',
  'gandharva',
  'rakshasa',
  'yaksha',
  'apsara',
  'naga',
];

/// Planet names as the model's system prompt writes them, in [defaultGrahas]
/// order.
const _planetNames = [
  'Sun',
  'Moon',
  'Mars',
  'Mercury',
  'Jupiter',
  'Venus',
  'Saturn',
  'Rahu',
  'Ketu',
];

/// Name → link URL. Beings → `being:{aditya}-{type}`, except Vishvavasu, the
/// one name in two cells (sign 5 and sign 12 gandharva), which gets
/// [vishvavasuMarker]. Being types, singular and plural (the model writes
/// both) → `being-type:{type}`. Planets → `planet:{body}`.
final Map<String, String> _urlForName = () {
  final map = <String, String>{};
  for (var row = 0; row < _beingTable.length; row++) {
    final aditya = _beingTable[row][0].toLowerCase();
    for (var col = 0; col < _columnTypes.length; col++) {
      final name = _beingTable[row][col];
      map[name] = map.containsKey(name)
          ? '$beingLinkScheme$vishvavasuMarker'
          : '$beingLinkScheme$aditya-${_columnTypes[col]}';
    }
  }
  for (final type in _columnTypes) {
    final name = '${type[0].toUpperCase()}${type.substring(1)}';
    map[name] = map['${name}s'] = '$beingTypeLinkScheme$type';
  }
  for (var i = 0; i < _planetNames.length; i++) {
    map[_planetNames[i]] = '$planetLinkScheme${defaultGrahas[i]}';
  }
  return map;
}();

/// Whole-word, case-sensitive alternation of every name, longest first so a
/// name that prefixes another can't shadow it.
final RegExp _namePattern = () {
  final names = _urlForName.keys.toList()
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

/// Rewrite every capitalised whole-word being, being-type or planet name in
/// [markdown] to a `[Name](scheme:target)` link, outside code and existing
/// links; [parseChatLink] decodes the URL on tap.
///
/// Vishvavasu gets a concrete slug when the reply names exactly one of its two
/// Adityas (Indra / Parjanya) — the model's own text settles it; otherwise it
/// gets [vishvavasuMarker] for [resolveBeingLink] to settle against the chart.
String linkChatNames(String markdown) {
  final hasIndra = _indra.hasMatch(markdown);
  final hasParjanya = _parjanya.hasMatch(markdown);
  final vishvavasuUrl =
      beingLinkScheme +
      (hasIndra == hasParjanya
          ? vishvavasuMarker
          : hasIndra
          ? 'indra-gandharva'
          : 'parjanya-gandharva');

  String linkSegment(String text) => text.replaceAllMapped(_namePattern, (m) {
    final name = m[0] ?? '';
    final url = _urlForName[name];
    if (url == null) return name;
    final target = url == '$beingLinkScheme$vishvavasuMarker'
        ? vishvavasuUrl
        : url;
    return '[$name]($target)';
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
