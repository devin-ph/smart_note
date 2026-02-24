import 'package:shared_preferences/shared_preferences.dart';
import 'note.dart';

class NoteStorage {
  static const String notesKey = 'notes';

  static Future<List<Note>> loadNotes() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString(notesKey);
    if (jsonString == null) return [];
    return Note.listFromJson(jsonString);
  }

  static Future<void> saveNotes(List<Note> notes) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(notesKey, Note.listToJson(notes));
  }
}
