import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';

import 'drawing_pad_screen.dart';
import 'note.dart';
import 'note_storage.dart';

class NoteEditScreen extends StatefulWidget {
  const NoteEditScreen({super.key, this.note, this.startChecklist = false});

  final Note? note;
  final bool startChecklist;

  @override
  State<NoteEditScreen> createState() => _NoteEditScreenState();
}

class _NoteEditScreenState extends State<NoteEditScreen> {
  late final TextEditingController _titleController;
  late final TextEditingController _contentController;
  final TextEditingController _newTagController = TextEditingController();
  final TextEditingController _newChecklistItemController =
      TextEditingController();

  late Note _workingNote;
  Timer? _debounce;
  bool _isSaving = false;
  bool _hasPendingChanges = false;
  final ImagePicker _imagePicker = ImagePicker();

  static const List<int> _paletteIndexes = [0, 1, 2, 3, 4];

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();

    _workingNote =
        widget.note ??
        Note(
          id: const Uuid().v4(),
          title: '',
          content: '',
          createdAt: now,
          updatedAt: now,
          isChecklist: widget.startChecklist,
        );

    _titleController = TextEditingController(text: _workingNote.title);
    _contentController = TextEditingController(text: _workingNote.content);
    _titleController.addListener(_onFieldChanged);
    _contentController.addListener(_onFieldChanged);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _titleController
      ..removeListener(_onFieldChanged)
      ..dispose();
    _contentController
      ..removeListener(_onFieldChanged)
      ..dispose();
    _newTagController.dispose();
    _newChecklistItemController.dispose();
    super.dispose();
  }

  void _onFieldChanged() {
    _hasPendingChanges = true;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      _saveNote();
    });
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _saveNote() async {
    if (_isSaving) {
      return;
    }

    final title = _titleController.text.trim();
    final content = _contentController.text.trim();
    final hasChecklistContent = _workingNote.checklistItems.any(
      (item) => item.text.trim().isNotEmpty,
    );

    if (title.isEmpty && content.isEmpty && !hasChecklistContent) {
      return;
    }

    setState(() {
      _isSaving = true;
    });

    final now = DateTime.now();
    _workingNote = Note(
      id: _workingNote.id,
      title: title,
      content: content,
      createdAt: _workingNote.createdAt,
      updatedAt: now,
      isPinned: _workingNote.isPinned,
      isArchived: _workingNote.isArchived,
      isDeleted: _workingNote.isDeleted,
      colorIndex: _workingNote.colorIndex,
      tags: List<String>.from(_workingNote.tags),
      isChecklist: _workingNote.isChecklist,
      checklistItems: List<ChecklistItem>.from(_workingNote.checklistItems),
      attachments: List<NoteAttachment>.from(_workingNote.attachments),
      deletedAt: _workingNote.deletedAt,
    );

    final notes = await NoteStorage.loadNotes();
    final index = notes.indexWhere((note) => note.id == _workingNote.id);
    if (index == -1) {
      notes.insert(0, _workingNote);
    } else {
      notes[index] = _workingNote;
    }

    await NoteStorage.saveNotes(notes);

    if (!mounted) {
      return;
    }

    setState(() {
      _isSaving = false;
      _hasPendingChanges = false;
    });
  }

  Future<void> _saveAndExit() async {
    _debounce?.cancel();
    await _saveNote();
    if (!mounted) {
      return;
    }
    Navigator.pop(context, true);
  }

  Future<void> _updateMeta({
    bool? pin,
    bool? archive,
    int? colorIndex,
    bool? checklistMode,
    List<String>? tags,
    List<ChecklistItem>? checklistItems,
    List<NoteAttachment>? attachments,
  }) async {
    _workingNote = Note(
      id: _workingNote.id,
      title: _titleController.text.trim(),
      content: _contentController.text.trim(),
      createdAt: _workingNote.createdAt,
      updatedAt: DateTime.now(),
      isPinned: pin ?? _workingNote.isPinned,
      isArchived: archive ?? _workingNote.isArchived,
      isDeleted: _workingNote.isDeleted,
      colorIndex: colorIndex ?? _workingNote.colorIndex,
      tags: tags ?? _workingNote.tags,
      isChecklist: checklistMode ?? _workingNote.isChecklist,
      checklistItems: checklistItems ?? _workingNote.checklistItems,
      attachments: attachments ?? _workingNote.attachments,
      deletedAt: _workingNote.deletedAt,
    );
    setState(() {
      _hasPendingChanges = true;
    });
    await _saveNote();
  }

  void _addTag() {
    final raw = _newTagController.text.trim().replaceAll('#', '');
    if (raw.isEmpty) {
      return;
    }

    if (_workingNote.tags.contains(raw)) {
      _newTagController.clear();
      return;
    }

    final tags = [..._workingNote.tags, raw]..sort();
    _newTagController.clear();
    _updateMeta(tags: tags);
  }

  void _removeTag(String tag) {
    final tags = _workingNote.tags.where((value) => value != tag).toList();
    _updateMeta(tags: tags);
  }

  void _addChecklistItem() {
    final text = _newChecklistItemController.text.trim();
    if (text.isEmpty) {
      return;
    }

    final nextItems = [
      ..._workingNote.checklistItems,
      ChecklistItem(id: const Uuid().v4(), text: text),
    ];
    _newChecklistItemController.clear();
    _updateMeta(checklistItems: nextItems);
  }

  void _toggleChecklistItem(ChecklistItem target, bool? value) {
    final nextItems = _workingNote.checklistItems.map((item) {
      if (item.id != target.id) {
        return item;
      }
      return ChecklistItem(
        id: item.id,
        text: item.text,
        isDone: value ?? false,
      );
    }).toList();
    _updateMeta(checklistItems: nextItems);
  }

  void _removeChecklistItem(ChecklistItem target) {
    final nextItems = _workingNote.checklistItems
        .where((item) => item.id != target.id)
        .toList();
    _updateMeta(checklistItems: nextItems);
  }

  Future<void> _addImageFromGallery() async {
    final picked = await _imagePicker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
      maxWidth: 2000,
    );
    if (picked == null) {
      return;
    }

    final bytes = await picked.readAsBytes();
    if (bytes.isEmpty) {
      return;
    }

    final nextAttachments = [
      ..._workingNote.attachments,
      NoteAttachment(
        id: const Uuid().v4(),
        type: 'image',
        base64Data: base64Encode(bytes),
        createdAt: DateTime.now(),
      ),
    ];

    await _updateMeta(attachments: nextAttachments);
  }

  Future<void> _addDrawing() async {
    final data = await Navigator.push<Uint8List>(
      context,
      MaterialPageRoute(builder: (_) => const DrawingPadScreen()),
    );
    if (data == null || data.isEmpty) {
      return;
    }

    final nextAttachments = [
      ..._workingNote.attachments,
      NoteAttachment(
        id: const Uuid().v4(),
        type: 'drawing',
        base64Data: base64Encode(data),
        createdAt: DateTime.now(),
      ),
    ];

    await _updateMeta(attachments: nextAttachments);
  }

  void _removeAttachment(NoteAttachment target) {
    final nextAttachments = _workingNote.attachments
        .where((attachment) => attachment.id != target.id)
        .toList();
    _updateMeta(attachments: nextAttachments);
  }

  Uint8List? _decodeAttachment(String value) {
    try {
      return base64Decode(value);
    } catch (_) {
      return null;
    }
  }

  Color _paletteColor(BuildContext context, int index) {
    final scheme = Theme.of(context).colorScheme;
    final colors = [
      scheme.surfaceContainer,
      scheme.primaryContainer.withValues(alpha: 0.55),
      scheme.secondaryContainer.withValues(alpha: 0.55),
      scheme.tertiaryContainer.withValues(alpha: 0.55),
      Color.alphaBlend(
        scheme.error.withValues(alpha: 0.12),
        scheme.surfaceContainer,
      ),
    ];
    return colors[index % colors.length];
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final doneCount = _workingNote.checklistItems
        .where((item) => item.isDone)
        .length;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) {
          return;
        }
        await _saveAndExit();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            widget.note == null ? 'Ghi chú mới' : 'Chỉnh sửa ghi chú',
          ),
          leading: IconButton(
            onPressed: _saveAndExit,
            icon: const Icon(Icons.arrow_back_rounded),
          ),
          actions: [
            IconButton(
              tooltip: _workingNote.isPinned ? 'Bỏ ghim' : 'Ghim ghi chú',
              onPressed: () => _updateMeta(pin: !_workingNote.isPinned),
              icon: Icon(
                _workingNote.isPinned
                    ? Icons.push_pin_rounded
                    : Icons.push_pin_outlined,
              ),
            ),
            IconButton(
              tooltip: _workingNote.isArchived ? 'Bỏ lưu trữ' : 'Lưu trữ',
              onPressed: () => _updateMeta(archive: !_workingNote.isArchived),
              icon: Icon(
                _workingNote.isArchived
                    ? Icons.archive_rounded
                    : Icons.archive_outlined,
              ),
            ),
            IconButton(
              tooltip: _workingNote.isChecklist
                  ? 'Chuyển về ghi chú văn bản'
                  : 'Chuyển sang checklist',
              onPressed: () =>
                  _updateMeta(checklistMode: !_workingNote.isChecklist),
              icon: Icon(
                _workingNote.isChecklist
                    ? Icons.sticky_note_2_rounded
                    : Icons.checklist_rounded,
              ),
            ),
            IconButton(
              tooltip: 'Thêm ảnh',
              onPressed: _addImageFromGallery,
              icon: const Icon(Icons.image_outlined),
            ),
            IconButton(
              tooltip: 'Vẽ tay',
              onPressed: _addDrawing,
              icon: const Icon(Icons.draw_rounded),
            ),
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Center(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 150),
                  child: _isSaving
                      ? Row(
                          key: const ValueKey('saving'),
                          children: [
                            SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: colorScheme.primary,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Đang lưu',
                              style: TextStyle(
                                color: colorScheme.primary,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        )
                      : Text(
                          _hasPendingChanges ? 'Chưa lưu' : 'Đã lưu',
                          key: const ValueKey('saved'),
                          style: TextStyle(
                            color: colorScheme.onSurfaceVariant,
                            fontSize: 12,
                          ),
                        ),
                ),
              ),
            ),
          ],
        ),
        body: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Card(
                  color: _paletteColor(context, _workingNote.colorIndex),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TextField(
                          controller: _titleController,
                          decoration: const InputDecoration(
                            hintText: 'Tiêu đề',
                            border: InputBorder.none,
                            isDense: true,
                          ),
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w700,
                          ),
                          maxLines: 2,
                        ),
                        const SizedBox(height: 6),
                        if (!_workingNote.isChecklist)
                          TextField(
                            controller: _contentController,
                            decoration: const InputDecoration(
                              hintText: 'Bắt đầu nhập nội dung...',
                              border: InputBorder.none,
                            ),
                            minLines: 8,
                            maxLines: null,
                            textCapitalization: TextCapitalization.sentences,
                            keyboardType: TextInputType.multiline,
                          )
                        else
                          Column(
                            children: [
                              TextField(
                                controller: _newChecklistItemController,
                                decoration: InputDecoration(
                                  hintText: 'Thêm mục công việc...',
                                  suffixIcon: IconButton(
                                    onPressed: _addChecklistItem,
                                    icon: const Icon(Icons.add_rounded),
                                  ),
                                ),
                                onSubmitted: (_) => _addChecklistItem(),
                              ),
                              const SizedBox(height: 8),
                              if (_workingNote.checklistItems.isEmpty)
                                const Padding(
                                  padding: EdgeInsets.symmetric(vertical: 8),
                                  child: Text(
                                    'Chưa có mục nào trong checklist.',
                                  ),
                                )
                              else
                                ..._workingNote.checklistItems.map(
                                  (item) => CheckboxListTile(
                                    dense: true,
                                    value: item.isDone,
                                    onChanged: (value) =>
                                        _toggleChecklistItem(item, value),
                                    title: Text(
                                      item.text,
                                      style: TextStyle(
                                        decoration: item.isDone
                                            ? TextDecoration.lineThrough
                                            : null,
                                      ),
                                    ),
                                    secondary: IconButton(
                                      onPressed: () =>
                                          _removeChecklistItem(item),
                                      icon: const Icon(Icons.close_rounded),
                                    ),
                                    controlAffinity:
                                        ListTileControlAffinity.leading,
                                    contentPadding: EdgeInsets.zero,
                                  ),
                                ),
                            ],
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  height: 40,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: _paletteIndexes.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 10),
                    itemBuilder: (context, index) {
                      final paletteIndex = _paletteIndexes[index];
                      final selected = _workingNote.colorIndex == paletteIndex;
                      return InkWell(
                        borderRadius: BorderRadius.circular(20),
                        onTap: () => _updateMeta(colorIndex: paletteIndex),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: _paletteColor(context, paletteIndex),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: selected
                                  ? colorScheme.primary
                                  : colorScheme.outlineVariant,
                              width: selected ? 2.4 : 1,
                            ),
                          ),
                          child: selected
                              ? Icon(
                                  Icons.check_rounded,
                                  size: 18,
                                  color: colorScheme.primary,
                                )
                              : null,
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _newTagController,
                        decoration: InputDecoration(
                          hintText: 'Thêm tag (vd: công_việc)',
                          suffixIcon: IconButton(
                            onPressed: _addTag,
                            icon: const Icon(Icons.add_rounded),
                          ),
                        ),
                        onSubmitted: (_) => _addTag(),
                      ),
                    ),
                  ],
                ),
                if (_workingNote.tags.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _workingNote.tags
                        .map(
                          (tag) => InputChip(
                            label: Text('#$tag'),
                            onDeleted: () => _removeTag(tag),
                          ),
                        )
                        .toList(),
                  ),
                ],
                if (_workingNote.attachments.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    'Ảnh & bản vẽ',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 120,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: _workingNote.attachments.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 8),
                      itemBuilder: (context, index) {
                        final attachment = _workingNote.attachments[index];
                        final bytes = _decodeAttachment(attachment.base64Data);
                        return Stack(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: bytes == null
                                  ? Container(
                                      width: 140,
                                      color:
                                          colorScheme.surfaceContainerHighest,
                                      alignment: Alignment.center,
                                      child: const Icon(
                                        Icons.broken_image_rounded,
                                      ),
                                    )
                                  : Image.memory(
                                      bytes,
                                      width: 140,
                                      height: 120,
                                      fit: BoxFit.cover,
                                    ),
                            ),
                            Positioned(
                              right: 4,
                              top: 4,
                              child: Material(
                                color: Colors.black45,
                                shape: const CircleBorder(),
                                child: InkWell(
                                  customBorder: const CircleBorder(),
                                  onTap: () => _removeAttachment(attachment),
                                  child: const Padding(
                                    padding: EdgeInsets.all(4),
                                    child: Icon(
                                      Icons.close_rounded,
                                      color: Colors.white,
                                      size: 14,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            Positioned(
                              left: 6,
                              bottom: 6,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.black54,
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(
                                  attachment.type == 'drawing'
                                      ? 'Bản vẽ'
                                      : 'Ảnh',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                Row(
                  children: [
                    Icon(
                      Icons.access_time_rounded,
                      size: 16,
                      color: colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _workingNote.isChecklist
                          ? 'Checklist: $doneCount/${_workingNote.checklistItems.length} hoàn thành'
                          : 'Văn bản thường',
                      style: TextStyle(
                        color: colorScheme.onSurfaceVariant,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'Cập nhật: ${_formatDate(_workingNote.updatedAt)}',
                      style: TextStyle(
                        color: colorScheme.onSurfaceVariant,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String _formatDate(DateTime dt) {
  final day = dt.day.toString().padLeft(2, '0');
  final month = dt.month.toString().padLeft(2, '0');
  final year = dt.year;
  final hour = dt.hour.toString().padLeft(2, '0');
  final minute = dt.minute.toString().padLeft(2, '0');
  return '$day/$month/$year · $hour:$minute';
}
