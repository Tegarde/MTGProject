import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../core/image_urls.dart';
import '../data/catalog/catalog_manifest.dart';

/// Card art from Scryfall's CDN, cached on disk.
///
/// Image terms forbid cropping out the copyright or artist line, recolouring,
/// blurring, or adding a watermark — so this widget only ever scales.
class CardImage extends StatelessWidget {
  const CardImage({
    super.key,
    required this.scryfallId,
    this.size = ImageSize.normal,
    this.back = false,
    this.hasImage = true,
    this.fit = BoxFit.contain,
    this.borderRadius = 12,
  });

  final String scryfallId;
  final ImageSize size;
  final bool back;

  /// False when the catalog reports `image_status = 'missing'`; the request is
  /// then skipped entirely rather than 404ing.
  final bool hasImage;
  final BoxFit fit;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(borderRadius);

    if (!hasImage) {
      return ClipRRect(borderRadius: radius, child: const _NoImage());
    }

    return ClipRRect(
      borderRadius: radius,
      child: CachedNetworkImage(
        imageUrl: cardImageUrl(scryfallId, size: size, back: back),
        httpHeaders: const {'User-Agent': kUserAgent},
        fit: fit,
        fadeInDuration: const Duration(milliseconds: 120),
        placeholder: (_, _) => const _Placeholder(),
        errorWidget: (_, _, _) => const _NoImage(),
      ),
    );
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder();

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: Theme.of(context).colorScheme.surfaceContainerHighest,
    child: const Center(
      child: SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
    ),
  );
}

class _NoImage extends StatelessWidget {
  const _NoImage();

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: Theme.of(context).colorScheme.surfaceContainerHighest,
    child: Icon(
      Icons.image_not_supported_outlined,
      color: Theme.of(context).colorScheme.outline,
    ),
  );
}
