import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/auth/auth_service.dart';
import '../data/auth/firebase_auth_service.dart';
import '../data/catalog/card_dao.dart';
import '../data/catalog/catalog_database.dart';
import '../data/catalog/set_dao.dart';
import '../data/collection/collection_repository.dart';
import '../data/collection/firestore_collection_repository.dart';
import '../models/app_user.dart';
import '../models/collection_entry.dart';
import '../models/mtg_card.dart';

/// Holds the open catalog once bootstrap has completed.
///
/// Deliberately plain state rather than a FutureProvider: the bootstrap screen
/// reports download progress itself, so nothing mutates providers mid-build.
class CatalogController extends Notifier<CatalogDatabase?> {
  @override
  CatalogDatabase? build() => null;

  void adopt(CatalogDatabase catalog) => state = catalog;
}

final catalogProvider = NotifierProvider<CatalogController, CatalogDatabase?>(
  CatalogController.new,
);

CatalogDatabase _requireCatalog(Ref ref) {
  final catalog = ref.watch(catalogProvider);
  if (catalog == null) {
    throw StateError('Catalog accessed before bootstrap completed');
  }
  return catalog;
}

final cardDaoProvider = Provider<CardDao>((ref) => CardDao(_requireCatalog(ref)));

final setDaoProvider = Provider<SetDao>((ref) => SetDao(_requireCatalog(ref)));

/// Active search filter, driven by the search screen.
class CardFilterController extends Notifier<CardFilter> {
  @override
  CardFilter build() => const CardFilter();

  void setText(String text) => state = state.copyWith(text: text);

  void toggleColor(String color) {
    final next = Set<String>.from(state.colors);
    if (!next.remove(color)) next.add(color);
    state = state.copyWith(colors: next);
  }

  void toggleRarity(String rarity) {
    final next = Set<String>.from(state.rarities);
    if (!next.remove(rarity)) next.add(rarity);
    state = state.copyWith(rarities: next);
  }

  void clear() => state = const CardFilter();
}

final cardFilterProvider = NotifierProvider<CardFilterController, CardFilter>(
  CardFilterController.new,
);

/// Search results for the active filter.
///
/// Recomputed whenever the filter changes; the search screen debounces input so
/// this does not run per keystroke.
final searchResultsProvider = Provider<List<MtgCard>>((ref) {
  final dao = ref.watch(cardDaoProvider);
  final filter = ref.watch(cardFilterProvider);
  return dao.search(filter);
});

// --- Auth -------------------------------------------------------------

final authServiceProvider = Provider<AuthService>((ref) => FirebaseAuthService());

/// The signed-in user, or `null` before sign-in / after sign-out.
final authStateProvider = StreamProvider<AppUser?>(
  (ref) => ref.watch(authServiceProvider).authStateChanges(),
);

// --- Collection ---------------------------------------------------------

/// Only valid once [authStateProvider] has a signed-in user; the app never
/// shows a screen that reads this before then (see `AuthGate`).
final collectionRepositoryProvider = Provider<CollectionRepository>((ref) {
  final user = ref.watch(authStateProvider).value;
  if (user == null) {
    throw StateError('Collection accessed before sign-in completed');
  }
  return FirestoreCollectionRepository(uid: user.uid);
});

/// The signed-in user's whole collection, live. A single app-level listener
/// per planning/04-firestore-model.md §5 — read this, do not re-subscribe
/// per widget.
final collectionEntriesProvider = StreamProvider<List<CollectionEntry>>(
  (ref) => ref.watch(collectionRepositoryProvider).watchAll(),
);

/// Total owned copies per card (summed across printings/finishes/conditions),
/// for the "you own N" indicator on search results and card detail. See
/// planning/06-decks.md §5 for why this must always aggregate first.
final ownedQuantityByOracleIdProvider = Provider<Map<String, int>>((ref) {
  final entries = ref.watch(collectionEntriesProvider).value ?? const [];
  final totals = <String, int>{};
  for (final entry in entries) {
    totals[entry.oracleId] = (totals[entry.oracleId] ?? 0) + entry.quantity;
  }
  return totals;
});
