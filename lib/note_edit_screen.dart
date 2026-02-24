import 'package:flutter/material.dart';
import 'note.dart';
import 'note_storage.dart';
import 'package:uuid/uuid.dart';

class NoteEditScreen extends StatefulWidget {
  final Note? note;
  const NoteEditScreen({super.key, this.note});

  @override
  State<NoteEditScreen> createState() => _NoteEditScreenState();
}

class _NoteEditScreenState extends State<NoteEditScreen> {
  late TextEditingController _titleController;
  late TextEditingController _contentController;
  late bool _isNew;
  late Note _note;
  bool _savedOnExit = false;

  @override
  void initState() {
    super.initState();
    _isNew = widget.note == null;
    _note = widget.note ?? Note(
      id: const Uuid().v4(),
      title: '',
      content: '',
      datetime: DateTime.now(),
    );
    _titleController = TextEditingController(text: _note.title);
    _contentController = TextEditingController(text: _note.content);
  }

  Future<void> _saveNote() async {
    final title = _titleController.text.trim();
    final content = _contentController.text.trim();
    if (title.isEmpty && content.isEmpty) {
      return;
    }

    _note = Note(
      id: _note.id,
      title: title,
      content: content,
      datetime: DateTime.now(),
    );

    final notes = await NoteStorage.loadNotes();
    final idx = notes.indexWhere((n) => n.id == _note.id);
    if (idx == -1) {
      notes.insert(0, _note);
    } else {
      notes[idx] = _note;
    }

    await NoteStorage.saveNotes(notes);
  }

  Future<void> _saveAndExit() async {
    if (_savedOnExit) {
      return;
    }
    _savedOnExit = true;
    await _saveNote();
    if (mounted) {
      Navigator.pop(context, true);
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (!didPop) {
          await _saveAndExit();
        }
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFF7F8FC),
        appBar: AppBar(
          title: Text(
            _isNew ? 'Tạo ghi chú' : 'Sửa ghi chú',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Center(
                child: Text(
                  'Auto-save',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: colorScheme.primary,
                  ),
                ),
              ),
            ),
          ],
        ),
        body: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
          child: Container(
            decoration: BoxDecoration(
              color: colorScheme.surface,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.06),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 10),
              child: Column(
                children: [
                  TextField(
                    controller: _titleController,
                    decoration: const InputDecoration(
                      hintText: 'Tiêu đề',
                      border: InputBorder.none,
                    ),
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 24, height: 1.2),
                    maxLines: 1,
                    autofocus: _isNew,
                  ),
                  Divider(color: colorScheme.outlineVariant.withValues(alpha: 0.5), height: 20),
                  Expanded(
                    child: TextField(
                      controller: _contentController,
                      decoration: const InputDecoration(
                        hintText: 'Nội dung...',
                        border: InputBorder.none,
                      ),
                      style: TextStyle(
                        fontSize: 16,
                        height: 1.5,
                        color: colorScheme.onSurface.withValues(alpha: 0.88),
                      ),
                      maxLines: null,
                      expands: true,
                      keyboardType: TextInputType.multiline,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
