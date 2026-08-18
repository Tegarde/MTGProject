import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/di.dart';
import '../../core/image_urls.dart';
import '../../models/collection_entry.dart';
import '../../widgets/account_menu_button.dart';
import '../../widgets/card_image.dart';
import '../card_detail/card_detail_screen.dart';

/// The signed-in user's owned cards, one row per distinct printing/finish/
/// condition/language, sorted by name. Backed by [collectionEntriesProvider]
/// — a single live listener per planning/04-firestore-model.md §5.
class CollectionScreen extends ConsumerWidget {
  const CollectionScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entriesAsync = ref.watch(collectionEntriesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Collection'), actions: const [AccountMenuButton()]),
      body: entriesAsync.when(
        data: (entries) {
          if (entries.isEmpty) {
            return const Center(child: Text('Nothing in your collection yet.'));
          }
          final sorted = [...entries]..sort((a, b) => a.name.compareTo(b.name));
          final totalCards = entries.fold<int>(0, (sum, e) => sum + e.quantity);
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(8),
                child: Text(
                  '$totalCards cards \u00b7 ${entries.length} entries',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: sorted.length,
                  itemBuilder: (context, index) => _CollectionRow(entry: sorted[index]),
                ),
              ),
            ],
          );
        },
        error: (error, _) => Center(child: Text('Could not load your collection: $error')),
        loading: () => const Center(child: CircularProgressIndicator()),
      ),
    );
  }
}

class _CollectionRow extends ConsumerWidget {
  const _CollectionRow({required this.entry});

  final CollectionEntry entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.read(collectionRepositoryProvider);

    return ListTile(
      leading: SizedBox(
        width: 44,
        height: 62,
        child: CardImage(
          scryfallId: entry.printingId,
          size: ImageSize.small,
          hasImage: true,
          fit: BoxFit.cover,
          borderRadius: 4,
        ),
      ),
      title: Text(entry.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
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
          Text('${entry.quantity}', style: Theme.of(context).textTheme.titleMedium),
          IconButton(
            onPressed: () => repo.updateQuantity(entry.entryId, entry.quantity + 1),
            icon: const Icon(Icons.add_circle_outline),
          ),
        ],
      ),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => CardDetailScreen(oracleId: entry.oracleId)),
      ),
    );
  }
}
