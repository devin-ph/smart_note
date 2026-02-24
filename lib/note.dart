import 'dart:convert';

class Note {
  String id;
  String title;
  String content;
  DateTime datetime;

  Note({
    required this.id,
    required this.title,
    required this.content,
    required this.datetime,
  });

  factory Note.fromJson(Map<String, dynamic> json) {
    return Note(
      id: json['id'],
      title: json['title'],
      content: json['content'],
      datetime: DateTime.parse(json['datetime']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'content': content,
      'datetime': datetime.toIso8601String(),
    };
  }

  static List<Note> listFromJson(String jsonString) {
    final List<dynamic> data = json.decode(jsonString);
    return data.map((e) => Note.fromJson(e)).toList();
  }

  static String listToJson(List<Note> notes) {
    return json.encode(notes.map((e) => e.toJson()).toList());
  }
}
