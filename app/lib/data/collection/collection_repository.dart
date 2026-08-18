import '../../models/collection_entry.dart';

/// Interface for the user's owned-card collection, kept separate from any
/// Firestore import.
///
/// planning/04-firestore-model.md §8: Firebase on Windows is beta, so no
/// widget or view model may import `cloud_firestore` directly. If the
/// Windows beta ever proves unstable, a REST-based implementation can be
/// swapped in through dependency injection with no UI changes.
abstract class CollectionRepository {
  /// All entries, live. One app-level listener per
  /// planning/04-firestore-model.md §5 — do not attach this per-widget.
  Stream<List<CollectionEntry>> watchAll();

  /// Adds [delta] copies of the printing/finish/condition/language combination
  /// described by [entry], creating the document if it does not exist yet.
  /// Idempotent and safe to call repeatedly (e.g. "own 1 more" taps).
  Future<void> addCopies(CollectionEntry entry, int delta);

  Future<void> updateQuantity(String entryId, int quantity);

  Future<void> updateNotes(String entryId, String notes);

  Future<void> remove(String entryId);
}
