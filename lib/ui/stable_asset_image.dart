import 'package:flutter/material.dart';

class StableAssetImage extends StatelessWidget {
  final String path;
  final double aspectRatio;
  final double borderRadius;
  final BoxFit fit;
  final WidgetBuilder? errorBuilder;

  const StableAssetImage({
    super.key,
    required this.path,
    this.aspectRatio = 512 / 896,
    this.borderRadius = 8,
    this.fit = BoxFit.cover,
    this.errorBuilder,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: AspectRatio(
        aspectRatio: aspectRatio,
        child: Image.asset(
          path,
          width: double.infinity,
          height: double.infinity,
          fit: fit,
          gaplessPlayback: true,
          errorBuilder: errorBuilder == null
              ? (_, _, _) => const SizedBox.shrink()
              : (_, _, _) => errorBuilder!(context),
        ),
      ),
    );
  }
}
