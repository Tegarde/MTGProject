import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/di.dart';
import '../../core/image_urls.dart';
import '../../models/mtg_card.dart';
import '../../widgets/account_menu_button.dart';
import '../../widgets/card_image.dart';
import '../card_detail/card_detail_screen.dart';

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _controller = TextEditingController();
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  /// Debounced so a query runs once the user pauses, not per keystroke.
  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      ref.read(cardFilterProvider.notifier).setText(value);
    });
  }

  @override
  Widget build(BuildContext context) {
    final catalog = ref.watch(catalogProvider);
    final results = ref.watch(searchResultsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Cards'),
        actions: const [AccountMenuButton()],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(64),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: SearchBar(
              controller: _controller,
              hintText: 'Search name or rules text',
              leading: const Icon(Icons.search),
              onChanged: _onChanged,
            ),
          ),
        ),
      ),
      body: results.isEmpty
          ? const Center(child: Text('No cards match that search.'))
          : ListView.builder(
              itemCount: results.length,
              itemBuilder: (context, index) => _CardRow(card: results[index]),
            ),
      bottomNavigationBar: catalog == null
          ? null
          : Padding(
              padding: const EdgeInsets.all(8),
              child: Text(
                '${catalog.cardCount} cards \u00b7 ${catalog.printingCount} printings '
                '\u00b7 ${catalog.setCount} sets \u00b7 catalog v${catalog.catalogVersion}',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
    );
  }
}

class _CardRow extends ConsumerWidget {
  const _CardRow({required this.card});

  final MtgCard card;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final printing = ref.read(cardDaoProvider).defaultPrintingOf(card);
    final owned = ref.watch(ownedQuantityByOracleIdProvider)[card.oracleId] ?? 0;

    return ListTile(
      leading: SizedBox(
        width: 44,
        height: 62,
        child: CardImage(
          scryfallId: card.defaultPrintingId,
          size: ImageSize.small,
          hasImage: printing?.hasImage ?? true,
          fit: BoxFit.cover,
          borderRadius: 4,
        ),
      ),
      title: Text(card.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        card.typeLine ?? '',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(card.manaCost ?? ''),
          if (owned > 0) ...[
            const SizedBox(height: 4),
            Text(
              'Owned $owned',
              style: Theme.of(
                context,
              ).textTheme.labelSmall?.copyWith(color: Theme.of(context).colorScheme.primary),
            ),
          ],
        ],
      ),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => CardDetailScreen(oracleId: card.oracleId)),
      ),
    );
  }
}
