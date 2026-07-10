import 'dart:developer' as dev;
import 'dart:io';

import 'package:flutter/services.dart' show AssetManifest, rootBundle;
import 'package:path_provider/path_provider.dart';

const _epheAssetDir = 'assets/ephe/';

String? _ephePath;

String? get currentSweEphePath => _ephePath;

Future<void> initSweEphePath() async {
  dev.log('swe: extracting ephe assets', name: 'IO');
  _ephePath = await _extractEpheAssets();
  dev.log('swe: ephePath=$_ephePath', name: 'IO');
}

Future<String?> _extractEpheAssets() async {
  final docs = await getApplicationSupportDirectory();
  final dir = Directory('${docs.path}/ephe');
  await dir.create(recursive: true);
  final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
  final assets =
      manifest
          .listAssets()
          .where((asset) => asset.startsWith(_epheAssetDir))
          .where(_isEpheArtifact)
          .toList()
        ..sort();
  for (final asset in assets) {
    final name = asset.split('/').last;
    final file = File('${dir.path}/$name');
    if (!await file.exists()) {
      final data = await rootBundle.load(asset);
      await file.writeAsBytes(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        flush: true,
      );
    }
  }
  return dir.path;
}

bool _isEpheArtifact(String asset) {
  final name = asset.split('/').last;
  return name.endsWith('.se1') ||
      name.endsWith('.eph') ||
      name == 'sefstars.txt';
}
