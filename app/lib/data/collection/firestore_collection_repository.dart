import 'package:cloud_firestore/cloud_firestore.dart';

import '../../models/collection_entry.dart';
import 'collection_repository.dart';

/// [CollectionRepository] backed by Cloud Firestore.
///
/// planning/04-firestore-model.md §8: this is the only file allowed to
/// import `cloud_firestore` for collection data. Everything else goes
/// through [CollectionRepository].
class FirestoreCollectionRepository implements CollectionRepository {
  FirestoreCollectionRepository({required String uid, FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance,
      _collection = (firestore ?? FirebaseFirestore.instance)
          .collection('users')
          .doc(uid)
          .collection('collection');

  final FirebaseFirestore _firestore;
  final CollectionReference<Map<String, dynamic>> _collection;

  @override
  Stream<List<CollectionEntry>> watchAll() => _collection.snapshots().map(
    (snapshot) => snapshot.docs.map((doc) => _fromDoc(doc.data())).toList(),
  );

  @override
  Future<void> addCopies(CollectionEntry entry, int delta) async {
    final doc = _collection.doc(entry.entryId);
    await _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(doc);
      if (snapshot.exists) {
        final current = (snapshot.data()!['quantity'] as num).toInt();
        transaction.update(doc, {
          'quantity': current + delta,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      } else {
        transaction.set(doc, {
          ...entry.toMap(),
          'quantity': delta,
          'addedAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
    });
  }

  @override
  Future<void> updateQuantity(String entryId, int quantity) async {
    if (quantity <= 0) {
      await remove(entryId);
      return;
    }
    await _collection.doc(entryId).update({
      'quantity': quantity,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  @override
  Future<void> updateNotes(String entryId, String notes) async {
    await _collection.doc(entryId).update({
      'notes': notes,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  @override
  Future<void> remove(String entryId) => _collection.doc(entryId).delete();

  CollectionEntry _fromDoc(Map<String, dynamic> data) => CollectionEntry.fromMap({
    ...data,
    'addedAt': (data['addedAt'] as Timestamp?)?.toDate(),
    'updatedAt': (data['updatedAt'] as Timestamp?)?.toDate(),
  });
}
