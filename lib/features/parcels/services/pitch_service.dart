import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/pitch.dart';

class PitchService {
  PitchService({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _collection =>
      _firestore.collection('pitches');

  Stream<List<Pitch>> watchPitches() {
    return _collection
        .orderBy('number')
        .snapshots()
        .map((snapshot) => snapshot.docs.map(Pitch.fromDoc).toList());
  }

  Future<void> createPitch(Pitch pitch) async {
    final doc = pitch.id.isEmpty
        ? _collection.doc()
        : _collection.doc(pitch.id);
    await doc.set({
      ...pitch.toMap(),
      'id': doc.id,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> updatePitch(Pitch pitch) async {
    await _collection.doc(pitch.id).update({
      ...pitch.toMap(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> deletePitch(String id) async {
    await _collection.doc(id).delete();
  }

  Future<bool> seedDefaultPitches() async {
    final snapshot = await _collection.limit(1).get();
    if (snapshot.docs.isNotEmpty) {
      return false;
    }

    final batch = _firestore.batch();
    for (var index = 1; index <= 45; index++) {
      final doc = _collection.doc('pitch_${index.toString().padLeft(2, '0')}');
      batch.set(doc, {
        'id': doc.id,
        'name': 'Parcela $index',
        'number': index,
        'zone': 'Glavna zona',
        'status': PitchStatus.available.name,
        'maxGuests': 4,
        'currentGuests': 0,
        'currentGuestCount': 0,
        'currentReservationId': null,
        'currentPrimaryGuestName': null,
        'occupiedFrom': null,
        'occupiedUntil': null,
        'hasElectricity': true,
        'hasWater': true,
        'notes': '',
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }

    await batch.commit();
    return true;
  }
}
