import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/di.dart';
import '../../models/collection_entry.dart';
import '../../models/mtg_card.dart';
import '../../models/printing.dart';

/// Bottom sheet that adds copies of one printing to the collection, in a
/// chosen finish/condition/language. Opened from the card detail screen.
class AddToCollectionSheet extends ConsumerStatefulWidget {
  const AddToCollectionSheet({super.key, required this.card, required this.printing});

  final MtgCard card;
  final Printing printing;

  static Future<void> show(BuildContext context, {required MtgCard card, required Printing printing}) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => AddToCollectionSheet(card: card, printing: printing),
    );
  }

  @override
  ConsumerState<AddToCollectionSheet> createState() => _AddToCollectionSheetState();
}

class _AddToCollectionSheetState extends ConsumerState<AddToCollectionSheet> {
  late String _finish;
  CardCondition _condition = CardCondition.nm;
  final _language = 'en';
  int _quantity = 1;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _finish = widget.printing.finishes.first;
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final entry = CollectionEntry(
      printingId: widget.printing.scryfallId,
      oracleId: widget.card.oracleId,
      setCode: widget.printing.setCode,
      name: widget.card.name,
      quantity: _quantity,
      finish: _finish,
      language: _language,
      condition: _condition,
    );
    try {
      await ref.read(collectionRepositoryProvider).addCopies(entry, _quantity);
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not save: $error')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Add to collection', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            '${widget.card.name} \u00b7 ${widget.printing.setCode.toUpperCase()} '
            '#${widget.printing.collectorNumber}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            initialValue: _finish,
            decoration: const InputDecoration(labelText: 'Finish'),
            items: [
              for (final finish in widget.printing.finishes)
                DropdownMenuItem(value: finish, child: Text(finish)),
            ],
            onChanged: (value) => setState(() => _finish = value ?? _finish),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<CardCondition>(
            initialValue: _condition,
            decoration: const InputDecoration(labelText: 'Condition'),
            items: [
              for (final condition in CardCondition.values)
                DropdownMenuItem(value: condition, child: Text(condition.code)),
            ],
            onChanged: (value) => setState(() => _condition = value ?? _condition),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Text('Quantity', style: Theme.of(context).textTheme.bodyMedium),
              const Spacer(),
              IconButton(
                onPressed: _quantity > 1 ? () => setState(() => _quantity--) : null,
                icon: const Icon(Icons.remove_circle_outline),
              ),
              Text('$_quantity', style: Theme.of(context).textTheme.titleMedium),
              IconButton(
                onPressed: () => setState(() => _quantity++),
                icon: const Icon(Icons.add_circle_outline),
              ),
            ],
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Add'),
          ),
        ],
      ),
    );
  }
}
