import 'dart:async';

import 'package:arrow_core/arrow_core.dart' as arrow;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../astro/being_uncertainty.dart';
import 'aditya_data.dart';
import 'being_content.dart';
import 'being_type_content.dart';
import 'planet_content.dart';

class AssetPreloader {
  static const _beingTypes = [
    'aditya',
    'rishi',
    'yaksha',
    'rakshasa',
    'gandharva',
    'apsara',
    'naga',
  ];

  const AssetPreloader._();

  static Future<void> precacheStaticAssets(BuildContext context) async {
    final imageConfig = createLocalImageConfiguration(context);

    await _precacheImages(
      [
        'assets/images/hero-dawn-temple_seed4830.webp',
        for (final type in _beingTypes) beingTypeGlyphPath(type),
        for (final type in _beingTypes) beingTypeEmblemPath(type),
        for (final name in defaultGrahas) planetImagePath(name),
      ].whereType<String>(),
      imageConfig,
    );

    await _precacheSvgs([
      ...planetGlyphs.values,
      for (final sign in adityaSigns.values) sign.glyph,
    ]);
  }

  static Future<void> precacheChartAssets(
    BuildContext context,
    arrow.Chart chart, {
    BeingUncertainty? uncertainty,
  }) async {
    final imageConfig = createLocalImageConfiguration(context);
    final detail = <String>{};
    final primary = <String>{};
    final uncertain = <String>{};

    for (final p in chart.grahas) {
      if (!defaultGrahas.contains(p.body.name)) continue;
      detail
        ..add(planetImagePath(p.body.name))
        ..add(beingTypeEmblemPath(p.trimsamsaBeing.type.name))
        ..add(beingTypeEmblemPath(p.horaBeing.type.name));
      primary
        ..add(
          beingImagePath(
            p.trimsamsaBeing.signNumber,
            p.trimsamsaBeing.type.name,
          ),
        )
        ..add(beingImagePath(p.horaBeing.signNumber, p.horaBeing.type.name));

      final options = uncertainty;
      if (options == null) continue;

      for (final being in options.trimsamsaFor(p.body.name)) {
        detail.add(beingTypeEmblemPath(being.type.name));
        uncertain.add(beingImagePath(being.signNumber, being.type.name));
      }
      for (final being in options.horaFor(p.body.name)) {
        detail.add(beingTypeEmblemPath(being.type.name));
        uncertain.add(beingImagePath(being.signNumber, being.type.name));
      }
    }

    await _precacheImages(detail.where((path) => path.isNotEmpty), imageConfig);
    await _precacheImages(
      primary.where((path) => path.isNotEmpty),
      imageConfig,
    );
    await _precacheImages(
      uncertain.where((path) => path.isNotEmpty && !primary.contains(path)),
      imageConfig,
    );
  }

  static Future<void> _precacheImages(
    Iterable<String> paths,
    ImageConfiguration config,
  ) async {
    for (final path in paths) {
      try {
        await _precacheImage(AssetImage(path), config);
      } catch (_) {
        // One failed preload should not prevent later, higher-value images.
      }
    }
  }

  static Future<void> _precacheSvgs(Iterable<String> paths) async {
    for (final path in paths) {
      try {
        await SvgAssetLoader(path).loadBytes(null);
      } catch (_) {
        // SVGs are decorative/contextual here; let the normal widget handle it.
      }
    }
  }

  static Future<void> _precacheImage(
    ImageProvider provider,
    ImageConfiguration config,
  ) {
    final completer = Completer<void>();
    final stream = provider.resolve(config);
    late ImageStreamListener listener;
    listener = ImageStreamListener(
      (image, _) {
        if (!completer.isCompleted) completer.complete();
        SchedulerBinding.instance.addPostFrameCallback((_) {
          image.dispose();
          stream.removeListener(listener);
        });
      },
      onError: (error, stackTrace) {
        if (!completer.isCompleted) {
          completer.completeError(error, stackTrace);
        }
        stream.removeListener(listener);
      },
    );
    stream.addListener(listener);
    return completer.future;
  }
}
