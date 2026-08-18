/// Derived Scryfall image URLs.
///
/// Verified against the live CDN; see planning/02-catalog-schema.md §5.
/// The catalog deliberately stores no image URLs — they are computed from the
/// printing's Scryfall id, which saves roughly 10 MB of catalog size.
library;

enum ImageSize {
  small,
  normal,
  large,
  png,
  artCrop,
  borderCrop;

  String get slug => switch (this) {
    ImageSize.small => 'small',
    ImageSize.normal => 'normal',
    ImageSize.large => 'large',
    ImageSize.png => 'png',
    ImageSize.artCrop => 'art_crop',
    ImageSize.borderCrop => 'border_crop',
  };
}

/// Builds the CDN URL for a printing.
///
/// Scryfall's API returns these with a `?<timestamp>` cache-buster; it is
/// omitted here so the on-disk image cache stays valid across catalog updates.
String cardImageUrl(
  String scryfallId, {
  ImageSize size = ImageSize.normal,
  bool back = false,
}) {
  final ext = size == ImageSize.png ? 'png' : 'jpg';
  final face = back ? 'back' : 'front';
  return 'https://cards.scryfall.io/${size.slug}/$face/'
      '${scryfallId[0]}/${scryfallId[1]}/$scryfallId.$ext';
}
