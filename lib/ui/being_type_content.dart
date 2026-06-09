import 'package:flutter/services.dart' show rootBundle;

class BeingTypeContent {
  final String type;
  final String role;
  final String subtitle;
  final String description;

  const BeingTypeContent({
    required this.type,
    required this.role,
    required this.subtitle,
    required this.description,
  });
}

String beingTypeEmblemPath(String type) =>
    'assets/images/emblems/${type}s.webp';

Future<Map<String, BeingTypeContent>> loadBeingTypeContent() async {
  final text =
      await rootBundle.loadString('assets/text/being-descriptions.txt');
  return _parseBeingTypes(text);
}

Map<String, BeingTypeContent> _parseBeingTypes(String text) {
  final results = <String, BeingTypeContent>{};
  final lines = text.split('\n');

  var i = 0;
  while (i < lines.length) {
    if (!lines[i].startsWith('--- ')) {
      i++;
      continue;
    }

    final header = lines[i].substring(4).trim();
    final dashIdx = header.indexOf(' - ');
    if (dashIdx < 0) {
      i++;
      continue;
    }
    final type = header.substring(0, dashIdx).trim();
    final role = header.substring(dashIdx + 3).trim();
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
    while (i < lines.length && !lines[i].startsWith('--- ')) {
      descLines.add(lines[i]);
      i++;
    }

    results[type.toLowerCase()] = BeingTypeContent(
      type: type,
      role: role,
      subtitle: subtitle,
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
