import 'dart:convert';

class ChecklistItem {
  String id;
  String text;
  bool isDone;

  ChecklistItem({required this.id, required this.text, this.isDone = false});

  factory ChecklistItem.fromJson(Map<String, dynamic> json) {
    return ChecklistItem(
      id: json['id'] ?? '',
      text: json['text'] ?? '',
      isDone: json['isDone'] ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {'id': id, 'text': text, 'isDone': isDone};
  }
}

class NoteAttachment {
  String id;
  String type;
  String base64Data;
  DateTime createdAt;

  NoteAttachment({
    required this.id,
    required this.type,
    required this.base64Data,
    required this.createdAt,
  });

  factory NoteAttachment.fromJson(Map<String, dynamic> json) {
    return NoteAttachment(
      id: json['id'] ?? '',
      type: json['type'] ?? 'image',
      base64Data: json['base64Data'] ?? '',
      createdAt: DateTime.tryParse(json['createdAt'] ?? '') ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type,
      'base64Data': base64Data,
      'createdAt': createdAt.toIso8601String(),
    };
  }
}

class Note {
  String id;
  String title;
  String content;
  DateTime createdAt;
  DateTime updatedAt;
  bool isPinned;
  bool isArchived;
  bool isDeleted;
  int colorIndex;
  List<String> tags;
  bool isChecklist;
  List<ChecklistItem> checklistItems;
  List<NoteAttachment> attachments;
  DateTime? deletedAt;

  Note({
    required this.id,
    required this.title,
    required this.content,
    required this.createdAt,
    required this.updatedAt,
    this.isPinned = false,
    this.isArchived = false,
    this.isDeleted = false,
    this.colorIndex = 0,
    this.tags = const [],
    this.isChecklist = false,
    this.checklistItems = const [],
    this.attachments = const [],
    this.deletedAt,
  });

  factory Note.fromJson(Map<String, dynamic> json) {
    final now = DateTime.now();
    final legacyDateString = json['datetime'];
    final createdAt =
        DateTime.tryParse(json['createdAt'] ?? '') ??
        DateTime.tryParse(legacyDateString ?? '') ??
        now;
    final updatedAt =
        DateTime.tryParse(json['updatedAt'] ?? '') ??
        DateTime.tryParse(legacyDateString ?? '') ??
        createdAt;

    final tagsRaw = json['tags'] as List<dynamic>?;
    final checklistRaw = json['checklistItems'] as List<dynamic>?;
    final attachmentsRaw = json['attachments'] as List<dynamic>?;

    return Note(
      id: json['id'],
      title: json['title'] ?? '',
      content: json['content'] ?? '',
      createdAt: createdAt,
      updatedAt: updatedAt,
      isPinned: json['isPinned'] ?? false,
      isArchived: json['isArchived'] ?? false,
      isDeleted: json['isDeleted'] ?? false,
      colorIndex: json['colorIndex'] ?? 0,
      tags: tagsRaw == null ? [] : tagsRaw.map((e) => e.toString()).toList(),
      isChecklist: json['isChecklist'] ?? false,
      checklistItems: checklistRaw == null
          ? []
          : checklistRaw
                .whereType<Map<String, dynamic>>()
                .map(ChecklistItem.fromJson)
                .toList(),
      attachments: attachmentsRaw == null
          ? []
          : attachmentsRaw
                .whereType<Map<String, dynamic>>()
                .map(NoteAttachment.fromJson)
                .toList(),
      deletedAt: DateTime.tryParse(json['deletedAt'] ?? ''),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'content': content,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'isPinned': isPinned,
      'isArchived': isArchived,
      'isDeleted': isDeleted,
      'colorIndex': colorIndex,
      'tags': tags,
      'isChecklist': isChecklist,
      'checklistItems': checklistItems.map((item) => item.toJson()).toList(),
      'attachments': attachments.map((item) => item.toJson()).toList(),
      'deletedAt': deletedAt?.toIso8601String(),
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
