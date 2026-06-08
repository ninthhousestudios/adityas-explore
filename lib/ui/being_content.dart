import 'package:flutter/services.dart' show rootBundle;

import 'aditya_data.dart';

class BeingContent {
  final String name;
  final String subtitle;
  final String description;
  final String reflections;

  const BeingContent({
    required this.name,
    required this.subtitle,
    required this.description,
    required this.reflections,
  });
}

String beingImagePath(int sign, String type) =>
    _beingImages[(sign, type)] ?? '';

String beingEmblemPath(String type) =>
    'assets/images/emblems/emblem-$type.webp';

String? adityaGlyphPath(int sign) => adityaSigns[sign]?.glyph;

String? adityaName(int sign) => adityaSigns[sign]?.name;

Future<Map<(int, String), BeingContent>> loadBeingContent() async {
  final nameToSign = <String, int>{
    for (final e in adityaSigns.entries) e.value.name.toLowerCase(): e.key,
  };

  final result = <(int, String), BeingContent>{};

  for (final entry in nameToSign.entries) {
    final adityaName = entry.key;
    final sign = entry.value;

    try {
      final text = await rootBundle.loadString('assets/text/$adityaName.txt');
      for (final (type, content) in _parseSections(text)) {
        result[(sign, type)] = content;
      }
    } catch (_) {}
  }

  return result;
}

List<(String, BeingContent)> _parseSections(String text) {
  final results = <(String, BeingContent)>[];
  final lines = text.split('\n');

  var i = 0;
  while (i < lines.length) {
    if (!lines[i].startsWith('--- ')) {
      i++;
      continue;
    }

    final parts = lines[i].substring(4).trim().split('|').map((s) => s.trim()).toList();
    if (parts.length < 2) {
      i++;
      continue;
    }
    final name = parts[0];
    final type = parts[1];
    i++;

    while (i < lines.length && lines[i].trim().isEmpty) {
      i++;
    }

    final subtitle = i < lines.length ? lines[i].trim() : '';
    i++;

    while (i < lines.length && lines[i].trim().isEmpty) {
      i++;
    }

    final descLines = <String>[];
    final reflLines = <String>[];
    var inReflections = false;

    while (i < lines.length && !lines[i].startsWith('--- ')) {
      if (lines[i].startsWith('=== Reflections')) {
        inReflections = true;
        i++;
        continue;
      }
      if (inReflections) {
        reflLines.add(lines[i]);
      } else {
        descLines.add(lines[i]);
      }
      i++;
    }

    results.add((
      type,
      BeingContent(
        name: name,
        subtitle: subtitle,
        description: _trimBlock(descLines),
        reflections: _trimBlock(reflLines),
      ),
    ));
  }

  return results;
}

String _trimBlock(List<String> lines) {
  final copy = List.of(lines);
  while (copy.isNotEmpty && copy.first.trim().isEmpty) {
    copy.removeAt(0);
  }
  while (copy.isNotEmpty && copy.last.trim().isEmpty) {
    copy.removeLast();
  }
  final paragraphs = <String>[];
  final current = StringBuffer();
  for (final line in copy) {
    if (line.trim().isEmpty) {
      if (current.isNotEmpty) {
        paragraphs.add(current.toString());
        current.clear();
      }
    } else {
      if (current.isNotEmpty) current.write(' ');
      current.write(line.trim());
    }
  }
  if (current.isNotEmpty) paragraphs.add(current.toString());
  return paragraphs.join('\n\n');
}

const _beingImages = <(int, String), String>{
  // 1 — Dhata
  (1, 'aditya'): 'assets/images/beings/aditya-dhata.webp',
  (1, 'rishi'): 'assets/images/beings/rishi-pulastya.webp',
  (1, 'yaksha'): 'assets/images/beings/yaksha-rathakrit.webp',
  (1, 'rakshasa'): 'assets/images/beings/rakshasa-heti.webp',
  (1, 'gandharva'): 'assets/images/beings/gandharva-tumburu.webp',
  (1, 'apsara'): 'assets/images/beings/apsara-kritasthali.webp',
  (1, 'naga'): 'assets/images/beings/naga-vasuki.webp',

  // 2 — Aryama
  (2, 'aditya'): 'assets/images/beings/aditya-aryama.webp',
  (2, 'rishi'): 'assets/images/beings/rishi-pulaha.webp',
  (2, 'yaksha'): 'assets/images/beings/yaksha-rathauja.webp',
  (2, 'rakshasa'): 'assets/images/beings/rakshasa-praheti.webp',
  (2, 'gandharva'): 'assets/images/beings/gandharva-narada.webp',
  (2, 'apsara'): 'assets/images/beings/apsara-punjikasthali.webp',
  (2, 'naga'): 'assets/images/beings/naga-kaccanira.webp',

  // 3 — Mitra
  (3, 'aditya'): 'assets/images/beings/aditya-mitra-2.webp',
  (3, 'rishi'): 'assets/images/beings/rishi-atri.webp',
  (3, 'yaksha'): 'assets/images/beings/yaksha-rathasvana-3.webp',
  (3, 'rakshasa'): 'assets/images/beings/rakshasa-paurusheya.webp',
  (3, 'gandharva'): 'assets/images/beings/gandharva-haha.webp',
  (3, 'apsara'): 'assets/images/beings/apsara-menaka.webp',
  (3, 'naga'): 'assets/images/beings/naga-takshaka.webp',

  // 4 — Varuna
  (4, 'aditya'): 'assets/images/beings/aditya-varuna.webp',
  (4, 'rishi'): 'assets/images/beings/rishi-vasishtha.webp',
  (4, 'yaksha'): 'assets/images/beings/yaksha-rathachitra.webp',
  (4, 'rakshasa'): 'assets/images/beings/rakshasa-chitrasvana.webp',
  (4, 'gandharva'): 'assets/images/beings/gandharva-huhu.webp',
  (4, 'apsara'): 'assets/images/beings/apsara-sahajanya.webp',
  (4, 'naga'): 'assets/images/beings/naga-shukra-3.webp',

  // 5 — Indra
  (5, 'aditya'): 'assets/images/beings/aditya-indra.webp',
  (5, 'rishi'): 'assets/images/beings/rishi-angiras.webp',
  (5, 'yaksha'): 'assets/images/beings/yaksha-shrota.webp',
  (5, 'rakshasa'): 'assets/images/beings/rakshasa-varya.webp',
  (5, 'gandharva'): 'assets/images/beings/gandharva-vishvavasu.webp',
  (5, 'apsara'): 'assets/images/beings/apsara-pramlocha.webp',
  (5, 'naga'): 'assets/images/beings/naga-elapattra.webp',

  // 6 — Vivasvan
  (6, 'aditya'): 'assets/images/beings/aditya-vivasvan-4.webp',
  (6, 'rishi'): 'assets/images/beings/rishi-bhrigu.webp',
  (6, 'yaksha'): 'assets/images/beings/yaksha-asarana.webp',
  (6, 'rakshasa'): 'assets/images/beings/rakshasa-vyaghra.webp',
  (6, 'gandharva'): 'assets/images/beings/gandharva-ugrasena.webp',
  (6, 'apsara'): 'assets/images/beings/apsara-anumlocha.webp',
  (6, 'naga'): 'assets/images/beings/naga-sankhapala.webp',

  // 7 — Tvashta
  (7, 'aditya'): 'assets/images/beings/aditya-tvashta.webp',
  (7, 'rishi'): 'assets/images/beings/rishi-jamadagni.webp',
  (7, 'yaksha'): 'assets/images/beings/yaksha-shatajit.webp',
  (7, 'rakshasa'): 'assets/images/beings/rakshasa-brahmapeta.webp',
  (7, 'gandharva'): 'assets/images/beings/gandharva-dritarashtra.webp',
  (7, 'apsara'): 'assets/images/beings/apsara-tilottama.webp',
  (7, 'naga'): 'assets/images/beings/naga-kambala.webp',

  // 8 — Vishnu
  (8, 'aditya'): 'assets/images/beings/aditya-vishnu.webp',
  (8, 'rishi'): 'assets/images/beings/rishi-vishvamitra.webp',
  (8, 'yaksha'): 'assets/images/beings/yaksha-satyajit.webp',
  (8, 'rakshasa'): 'assets/images/beings/rakshasa-makhapeta.webp',
  (8, 'gandharva'): 'assets/images/beings/gandharva-suryavarcas.webp',
  (8, 'apsara'): 'assets/images/beings/apsara-rambha.webp',
  (8, 'naga'): 'assets/images/beings/naga-ashvatara.webp',

  // 9 — Amshu
  (9, 'aditya'): 'assets/images/beings/aditya-amshu.webp',
  (9, 'rishi'): 'assets/images/beings/rishi-kashyapa.webp',
  (9, 'yaksha'): 'assets/images/beings/yaksha-tarkshya.webp',
  (9, 'rakshasa'): 'assets/images/beings/rakshasa-vidyucchatru.webp',
  (9, 'gandharva'): 'assets/images/beings/gandharva-rtasena.webp',
  (9, 'apsara'): 'assets/images/beings/apsara-urvashi.webp',
  (9, 'naga'): 'assets/images/beings/naga-mahasankha.webp',

  // 10 — Bhaga
  (10, 'aditya'): 'assets/images/beings/aditya-bhaga.webp',
  (10, 'rishi'): 'assets/images/beings/rishi-kratu.webp',
  (10, 'yaksha'): 'assets/images/beings/yaksha-arishtanemi.webp',
  (10, 'rakshasa'): 'assets/images/beings/rakshasa-sphurja.webp',
  (10, 'gandharva'): 'assets/images/beings/gandharva-urnayu.webp',
  (10, 'apsara'): 'assets/images/beings/apsara-purvacitta.webp',
  (10, 'naga'): 'assets/images/beings/naga-karkotaka.webp',

  // 11 — Pusha
  (11, 'aditya'): 'assets/images/beings/aditya-pusha-2.webp',
  (11, 'rishi'): 'assets/images/beings/rishi-gautama.webp',
  (11, 'yaksha'): 'assets/images/beings/yaksha-susena.webp',
  (11, 'rakshasa'): 'assets/images/beings/rakshasa-vata.webp',
  (11, 'gandharva'): 'assets/images/beings/gandharva-suruci.webp',
  (11, 'apsara'): 'assets/images/beings/apsara-ghritaci.webp',
  (11, 'naga'): 'assets/images/beings/naga-dhananjaya.webp',

  // 12 — Parjanya
  (12, 'aditya'): 'assets/images/beings/aditya-parjanya.webp',
  (12, 'rishi'): 'assets/images/beings/rishi-bharadvaja.webp',
  (12, 'yaksha'): 'assets/images/beings/yaksha-senajit.webp',
  (12, 'rakshasa'): 'assets/images/beings/rakshasa-varcas.webp',
  (12, 'gandharva'): 'assets/images/beings/gandharva-vishvavasu-parjanya.webp',
  (12, 'apsara'): 'assets/images/beings/apsara-visvaci.webp',
  (12, 'naga'): 'assets/images/beings/naga-airavata.webp',
};
