import 'package:shared_preferences/shared_preferences.dart';
import 'note.dart';

class NoteStorage {
  static const String notesKey = 'notes';
  static const String themeModeKey = 'theme_mode';
  static const String viewModeKey = 'view_mode';

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
}
