import 'dart:developer' as dev;
import 'dart:io';

import 'package:flutter/services.dart' show AssetManifest, rootBundle;
import 'package:path_provider/path_provider.dart';
import 'package:swisseph/swisseph.dart';

const _epheAssetDir = 'assets/ephe/';

String? _ephePath;

String? get currentSweEphePath => _ephePath;

SwissEph openSwissEph(String? ephePath) {
  final swe = _loadNativeLibrary();
  if (ephePath != null) swe.setEphePath(ephePath);
  return swe;
}

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

SwissEph _loadNativeLibrary() {
  final exeDir = File(Platform.resolvedExecutable).parent.path;
  final candidates = [
    '$exeDir/lib/libswisseph.so',
    '$exeDir/lib/libswisseph.dylib',
    '$exeDir/../Frameworks/libswisseph.dylib',
    '$exeDir/Frameworks/libswisseph.dylib',
    '$exeDir/swisseph.dll',
  ];
  for (final path in candidates) {
    if (File(path).existsSync()) return SwissEph(path);
  }

  if (Platform.isAndroid) return SwissEph('libswisseph.so');
  if (Platform.isIOS || Platform.isMacOS) {
    try {
      return SwissEph('swisseph_native.framework/swisseph_native');
    } catch (_) {}
  }

  final bareName = Platform.isWindows
      ? 'swisseph.dll'
      : Platform.isLinux
      ? 'libswisseph.so'
      : 'libswisseph.dylib';
  try {
    return SwissEph(bareName);
  } catch (_) {}

  try {
    return SwissEph.find();
  } catch (_) {}
  final libPath = _findLibraryInDartTool();
  if (libPath != null) return SwissEph(libPath);

  throw StateError(
    'libswisseph not found. Ensure native assets are enabled and run '
    'flutter pub get. On Apple platforms, ensure swisseph_native is installed.',
  );
}

String? _findPackageConfig() {
  final cwdConfig = File(
    '${Directory.current.path}/.dart_tool/package_config.json',
  );
  if (cwdConfig.existsSync()) return cwdConfig.path;

  var dir = File(Platform.resolvedExecutable).parent;
  for (var i = 0; i < 12; i++) {
    final candidate = File('${dir.path}/.dart_tool/package_config.json');
    if (candidate.existsSync()) return candidate.path;
    final parent = dir.parent;
    if (parent.path == dir.path) break;
    dir = parent;
  }
  return null;
}

String? _findLibraryInDartTool() {
  final pkgConfig = _findPackageConfig();
  if (pkgConfig == null) return null;

  final dartToolDir = File(pkgConfig).parent;
  if (!dartToolDir.existsSync()) return null;

  const libNames = ['libswisseph.so', 'libswisseph.dylib', 'swisseph.dll'];
  try {
    for (final entity in dartToolDir.listSync(recursive: true)) {
      if (entity is File &&
          libNames.any((name) => entity.path.endsWith(name))) {
        return entity.path;
      }
    }
  } catch (_) {}
  return null;
}
