import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/di.dart';
import '../../core/image_urls.dart';
import '../../models/card_face.dart';
import '../../models/collection_entry.dart';
import '../../models/mtg_card.dart';
import '../../models/printing.dart';
import '../../widgets/card_image.dart';
import '../collection/add_to_collection_sheet.dart';

class CardDetailScreen extends ConsumerStatefulWidget {
  const CardDetailScreen({super.key, required this.oracleId});

  final String oracleId;

  @override
  ConsumerState<CardDetailScreen> createState() => _CardDetailScreenState();
}

class _CardDetailScreenState extends ConsumerState<CardDetailScreen> {
  bool _showBack = false;

  @override
  Widget build(BuildContext context) {
    final dao = ref.watch(cardDaoProvider);
    final card = dao.byOracleId(widget.oracleId);
    if (card == null) {
      return const Scaffold(body: Center(child: Text('Card not found')));
    }

    final faces = dao.facesOf(card.oracleId);
    final printings = dao.printingsOf(card.oracleId);
    final shown = printings.firstWhere(
      (p) => p.scryfallId == card.defaultPrintingId,
      orElse: () => printings.first,
    );

    return Scaffold(
      appBar: AppBar(title: Text(card.name)),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => AddToCollectionSheet.show(context, card: card, printing: shown),
        icon: const Icon(Icons.add),
        label: const Text('Add to collection'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 340),
              child: AspectRatio(
                aspectRatio: 488 / 680,
                child: CardImage(
                  scryfallId: shown.scryfallId,
                  hasImage: shown.hasImage,
                  back: _showBack,
                ),
              ),
            ),
          ),
          if (shown.twoSidedImage)
            Center(
              child: TextButton.icon(
                onPressed: () => setState(() => _showBack = !_showBack),
                icon: const Icon(Icons.flip),
                label: Text(_showBack ? 'Show front' : 'Show back'),
              ),
            ),
          const SizedBox(height: 16),
          if (faces.isEmpty) _OracleText(card: card) else _Faces(faces: faces),
          const SizedBox(height: 24),
          _OwnedSection(oracleId: card.oracleId),
          const SizedBox(height: 24),
          Text(
            'Printings (${printings.length})',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          ...printings.map((p) => _PrintingRow(printing: p)),
          const SizedBox(height: 80), // clears the FAB
        ],
      ),
    );
  }
}

class _OracleText extends StatelessWidget {
  const _OracleText({required this.card});

  final MtgCard card;

  @override
  Widget build(BuildContext context) {
    final stats = [
      if (card.power != null && card.toughness != null) '${card.power}/${card.toughness}',
      if (card.loyalty != null) 'Loyalty ${card.loyalty}',
      if (card.defense != null) 'Defense ${card.defense}',
    ].join(' \u00b7 ');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${card.typeLine ?? ''}   ${card.manaCost ?? ''}',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 8),
        if (card.oracleText != null) Text(card.oracleText!),
        if (stats.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(stats, style: Theme.of(context).textTheme.labelLarge),
        ],
      ],
    );
  }
}

class _Faces extends StatelessWidget {
  const _Faces({required this.faces});

  final List<CardFace> faces;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      for (final face in faces) ...[
        Text(face.name, style: Theme.of(context).textTheme.titleSmall),
        Text('${face.typeLine ?? ''}   ${face.manaCost ?? ''}'),
        if (face.oracleText != null) ...[
          const SizedBox(height: 4),
          Text(face.oracleText!),
        ],
        if (face.power != null && face.toughness != null)
          Text('${face.power}/${face.toughness}'),
        const SizedBox(height: 16),
      ],
    ],
  );
}

class _PrintingRow extends ConsumerWidget {
  const _PrintingRow({required this.printing});

  final Printing printing;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final set = ref.read(setDaoProvider).byCode(printing.setCode);
    final finishes = printing.finishes.join(', ');

    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: SizedBox(
        width: 32,
        height: 44,
        child: CardImage(
          scryfallId: printing.scryfallId,
          size: ImageSize.small,
          hasImage: printing.hasImage,
          fit: BoxFit.cover,
          borderRadius: 3,
        ),
      ),
      title: Text(set?.name ?? printing.setCode.toUpperCase()),
      subtitle: Text(
        '#${printing.collectorNumber} \u00b7 ${printing.rarity} \u00b7 $finishes',
      ),
    );
  }
}

/// Collection entries owned for this card, across every printing/finish/
/// condition. Aggregation lives in [ownedQuantityByOracleIdProvider] for the
/// total shown elsewhere; this lists the individual entries so each can be
/// adjusted or removed.
class _OwnedSection extends ConsumerWidget {
  const _OwnedSection({required this.oracleId});

  final String oracleId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entries = (ref.watch(collectionEntriesProvider).value ?? const <CollectionEntry>[])
        .where((e) => e.oracleId == oracleId)
        .toList();

    if (entries.isEmpty) {
      return Text(
        'Not in your collection yet.',
        style: Theme.of(context).textTheme.bodySmall,
      );
    }

    final total = entries.fold<int>(0, (sum, e) => sum + e.quantity);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('You own $total', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 4),
        for (final entry in entries) _OwnedRow(entry: entry),
      ],
    );
  }
}

class _OwnedRow extends ConsumerWidget {
  const _OwnedRow({required this.entry});

  final CollectionEntry entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.read(collectionRepositoryProvider);

    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      title: Text(
        '${entry.setCode.toUpperCase()} \u00b7 ${entry.finish} \u00b7 '
        '${entry.condition.code} \u00b7 ${entry.language}',
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            onPressed: () => repo.updateQuantity(entry.entryId, entry.quantity - 1),
            icon: const Icon(Icons.remove_circle_outline),
          ),
          Text('${entry.quantity}'),
          IconButton(
            onPressed: () => repo.updateQuantity(entry.entryId, entry.quantity + 1),
            icon: const Icon(Icons.add_circle_outline),
          ),
        ],
      ),
    );
  }
}
