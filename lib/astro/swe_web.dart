import 'dart:developer' as dev;

import 'package:arrow_swe/arrow_swe.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:swisseph_rs/swisseph_rs.dart' as swe;
import 'package:web/web.dart' as web;

import 'swe_compute.dart';

const _epheAssets = <String>[
  'assets/ephe/seas_18.se1',
  'assets/ephe/semo_18.se1',
  'assets/ephe/sepl_18.se1',
  'assets/ephe/sefstars.txt',
];

String? get currentSweEphePath => '/ephe';

Future<void> initSweEphePath() async {
  dev.log('swe: loading WASM module', name: 'IO');
  final base = web.document.baseURI;
  final modulePath = Uri.parse(base).resolve('swisseph_ffi').toString();
  dev.log('swe: loading from $modulePath', name: 'IO');
  await swe.initializeWasm(modulePath);
  for (final asset in _epheAssets) {
    final name = asset.split('/').last;
    final data = await rootBundle.load(asset);
    swe.loadEpheFile(
      name,
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
    );
  }
  workerFacade = SweFacade.create(ephePath: '/ephe');
  dev.log('swe: WASM loaded, ephe in MEMFS at /ephe', name: 'IO');
}
