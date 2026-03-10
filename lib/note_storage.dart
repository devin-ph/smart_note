import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import 'note.dart';

class NoteStorage {
  static const String notesKey = 'notes';
  static const String themeModeKey = 'theme_mode';
  static const String viewModeKey = 'view_mode';
  static const String deviceIdKey = 'device_id';
  static const String ownerIdField = 'ownerId';
  static const String deviceIdField = 'deviceId';
  static const String notesCollection = 'notes';

  static Future<List<Note>> loadNotes() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString(notesKey);
    final localNotes = jsonString == null
        ? <Note>[]
        : Note.listFromJson(jsonString);

    final cloudNotes = await _loadNotesFromCloud();
    if (cloudNotes == null) {
      return localNotes;
    }

    if (cloudNotes.isEmpty) {
      return localNotes;
    }

    final merged = _mergeNotes(localNotes, cloudNotes);
    await prefs.setString(notesKey, Note.listToJson(merged));
    return merged;
  }

  static Future<void> saveNotes(List<Note> notes) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(notesKey, Note.listToJson(notes));
    await _saveNotesToCloud(notes);
  }

  static Future<String> loadThemeMode() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(themeModeKey) ?? 'system';
  }

  static Future<void> saveThemeMode(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(themeModeKey, value);
  }

  static Future<String> loadViewMode() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(viewModeKey) ?? 'grid';
  }

  static Future<void> saveViewMode(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(viewModeKey, value);
  }

  static Stream<List<Note>> watchNotes() async* {
    if (Firebase.apps.isEmpty) {
      yield <Note>[];
      return;
    }

    try {
      final firestore = FirebaseFirestore.instance;
      final ownerId = await _getOwnerId();

      yield* firestore
          .collection(notesCollection)
          .where(ownerIdField, isEqualTo: ownerId)
          .snapshots()
          .map((snapshot) {
            final notes = snapshot.docs.map((doc) {
              final data = Map<String, dynamic>.from(doc.data());
              data.remove(ownerIdField);
              data.remove(deviceIdField);
              return Note.fromJson(data);
            }).toList();

            notes.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
            return notes;
          });
    } catch (_) {
      yield <Note>[];
    }
  }

  static Future<String> _getOrCreateDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getString(deviceIdKey);
    if (existing != null && existing.isNotEmpty) {
      return existing;
    }

    final generated = const Uuid().v4();
    await prefs.setString(deviceIdKey, generated);
    return generated;
  }

  static Future<List<Note>?> _loadNotesFromCloud() async {
    if (Firebase.apps.isEmpty) {
      return null;
    }

    try {
      final firestore = FirebaseFirestore.instance;
      final ownerId = await _getOwnerId();
      final deviceId = await _getOrCreateDeviceId();

      final ownerSnapshot = await firestore
          .collection(notesCollection)
          .where(ownerIdField, isEqualTo: ownerId)
          .get();

      QuerySnapshot<Map<String, dynamic>>? legacySnapshot;
      if (ownerId != deviceId) {
        legacySnapshot = await firestore
            .collection(notesCollection)
            .where(deviceIdField, isEqualTo: deviceId)
            .get();
      }

      final allDocs = [
        ...ownerSnapshot.docs,
        if (legacySnapshot != null) ...legacySnapshot.docs,
      ];

      final dedup = <String, Note>{};
      for (final doc in allDocs) {
        final data = Map<String, dynamic>.from(doc.data());
        data.remove(ownerIdField);
        data.remove(deviceIdField);
        final note = Note.fromJson(data);
        final existing = dedup[note.id];
        if (existing == null || note.updatedAt.isAfter(existing.updatedAt)) {
          dedup[note.id] = note;
        }
      }

      final notes = dedup.values.toList();

      notes.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      return notes;
    } catch (_) {
      return null;
    }
  }

  static Future<void> _saveNotesToCloud(List<Note> notes) async {
    if (Firebase.apps.isEmpty) {
      return;
    }

    try {
      final firestore = FirebaseFirestore.instance;
      final ownerId = await _getOwnerId();
      final deviceId = await _getOrCreateDeviceId();

      final collection = firestore.collection(notesCollection);
      final ownerSnapshot = await collection
          .where(ownerIdField, isEqualTo: ownerId)
          .get();

      QuerySnapshot<Map<String, dynamic>>? legacySnapshot;
      if (ownerId != deviceId) {
        legacySnapshot = await collection
            .where(deviceIdField, isEqualTo: deviceId)
            .get();
      }

      final existingIds = {
        ...ownerSnapshot.docs.map((doc) => doc.id),
        if (legacySnapshot != null) ...legacySnapshot.docs.map((doc) => doc.id),
      };
      final incomingIds = notes.map((note) => note.id).toSet();

      final batch = firestore.batch();

      for (final note in notes) {
        final data = note.toJson()
          ..[ownerIdField] = ownerId
          ..[deviceIdField] = deviceId;
        batch.set(collection.doc(note.id), data);
      }

      for (final removedId in existingIds.difference(incomingIds)) {
        batch.delete(collection.doc(removedId));
      }

      await batch.commit();
    } catch (_) {
    }
  }

  static Future<String> _getOwnerId() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null && user.uid.isNotEmpty) {
      return user.uid;
    }
    return _getOrCreateDeviceId();
  }

  static List<Note> _mergeNotes(List<Note> localNotes, List<Note> cloudNotes) {
    final byId = <String, Note>{};

    for (final note in localNotes) {
      byId[note.id] = note;
    }

    for (final cloudNote in cloudNotes) {
      final local = byId[cloudNote.id];
      if (local == null || cloudNote.updatedAt.isAfter(local.updatedAt)) {
        byId[cloudNote.id] = cloudNote;
      }
    }

    final merged = byId.values.toList();
    merged.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return merged;
  }
}
