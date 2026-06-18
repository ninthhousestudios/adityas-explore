import 'package:flutter/services.dart' show rootBundle;

class PlanetContent {
  final String name;
  final String description;

  const PlanetContent({required this.name, required this.description});
}

String planetImagePath(String name) =>
    'assets/images/planets/${name.toLowerCase()}.webp';

Future<Map<String, PlanetContent>> loadPlanetContent() async {
  final text = await rootBundle.loadString(
    'assets/text/planet-descriptions.txt',
  );
  return _parsePlanets(text);
}

Map<String, PlanetContent> _parsePlanets(String text) {
  final results = <String, PlanetContent>{};
  final lines = text.split('\n');

  var i = 0;
  while (i < lines.length) {
    if (!lines[i].startsWith('--- ')) {
      i++;
      continue;
    }

    final name = lines[i].substring(4).trim();
    i++;

    while (i < lines.length && lines[i].trim().isEmpty) {
      i++;
    }

    final descLines = <String>[];
    while (i < lines.length && !lines[i].startsWith('--- ')) {
      descLines.add(lines[i]);
      i++;
    }

    results[name.toLowerCase()] = PlanetContent(
      name: name,
      description: _trimBlock(descLines),
    );
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
