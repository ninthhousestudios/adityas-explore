import 'dart:developer' as dev;

import 'package:arrow_swe/arrow_swe.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:swisseph/swisseph.dart';

import 'swe_compute.dart';

const _epheAssets = <String>[
  'assets/ephe/seas_18.se1',
  'assets/ephe/semo_18.se1',
  'assets/ephe/sepl_18.se1',
];

SwissEph? _instance;

String? get currentSweEphePath => '/ephe';

SwissEph openSwissEph(String? ephePath) {
  final swe = _instance;
  if (swe != null) return swe;
  throw StateError('SwissEph not loaded — call initSweEphePath() first.');
}

Future<void> initSweEphePath() async {
  dev.log('swe: loading WASM module', name: 'IO');
  final swe = await SwissEph.load();
  for (final asset in _epheAssets) {
    final name = asset.split('/').last;
    final data = await rootBundle.load(asset);
    swe.loadEpheFile(
      name,
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
    );
  }
  swe.setEphePath('/ephe');
  _instance = swe;
  workerFacade = SweFacade(swe, ephePath: '/ephe');
  dev.log('swe: WASM loaded, ephe in MEMFS at /ephe', name: 'IO');
}
