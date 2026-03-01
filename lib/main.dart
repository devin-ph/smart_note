import 'package:flutter/material.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'dart:convert';
import 'dart:typed_data';

import 'note.dart';
import 'note_edit_screen.dart';
import 'note_storage.dart';

void main() {
  runApp(const SmartNoteApp());
}

enum AppThemeMode { system, light, dark }

enum NoteSort { updatedDesc, updatedAsc, titleAsc }

enum NoteBucket { notes, archived, trash }

class SmartNoteApp extends StatefulWidget {
  const SmartNoteApp({super.key});

  @override
  State<SmartNoteApp> createState() => _SmartNoteAppState();
}

class _SmartNoteAppState extends State<SmartNoteApp> {
  AppThemeMode _themeMode = AppThemeMode.system;

  @override
  void initState() {
    super.initState();
    _loadThemeMode();
  }

  Future<void> _loadThemeMode() async {
    final value = await NoteStorage.loadThemeMode();
    if (!mounted) {
      return;
    }
    setState(() {
      _themeMode = _parseThemeMode(value);
    });
  }

  Future<void> _updateThemeMode(AppThemeMode mode) async {
    setState(() {
      _themeMode = mode;
    });
    await NoteStorage.saveThemeMode(mode.name);
  }

  ThemeMode get _flutterThemeMode {
    switch (_themeMode) {
      case AppThemeMode.light:
        return ThemeMode.light;
      case AppThemeMode.dark:
        return ThemeMode.dark;
      case AppThemeMode.system:
        return ThemeMode.system;
    }
  }

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFF4F46E5);

    return MaterialApp(
      title: 'Smart Note',
      debugShowCheckedModeBanner: false,
      themeMode: _flutterThemeMode,
      theme: _buildTheme(Brightness.light, seed),
      darkTheme: _buildTheme(Brightness.dark, seed),
      home: HomeScreen(
        themeMode: _themeMode,
        onThemeModeChanged: _updateThemeMode,
      ),
    );
  }

  ThemeData _buildTheme(Brightness brightness, Color seed) {
    final base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: ColorScheme.fromSeed(
        seedColor: seed,
        brightness: brightness,
      ),
    );

    final scheme = base.colorScheme;
    return base.copyWith(
      scaffoldBackgroundColor: scheme.surface,
      appBarTheme: AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: Colors.transparent,
        foregroundColor: scheme.onSurface,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
    );
  }
}

AppThemeMode _parseThemeMode(String raw) {
  switch (raw) {
    case 'light':
      return AppThemeMode.light;
    case 'dark':
      return AppThemeMode.dark;
    default:
      return AppThemeMode.system;
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.themeMode,
    required this.onThemeModeChanged,
  });

  final AppThemeMode themeMode;
  final ValueChanged<AppThemeMode> onThemeModeChanged;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final TextEditingController _searchController = TextEditingController();

  List<Note> _notes = [];
  bool _isLoading = true;
  bool _isGridMode = true;
  NoteSort _sort = NoteSort.updatedDesc;
  NoteBucket _bucket = NoteBucket.notes;
  String? _selectedTag;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    final notes = await NoteStorage.loadNotes();
    final viewMode = await NoteStorage.loadViewMode();

    if (!mounted) {
      return;
    }

    setState(() {
      _notes = notes;
      _isGridMode = viewMode != 'list';
      _isLoading = false;
    });
  }

  Future<void> _openEditor({Note? note, bool startChecklist = false}) async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) =>
            NoteEditScreen(note: note, startChecklist: startChecklist),
      ),
    );

    if (changed == true) {
      await _loadData();
    }
  }

  Future<void> _toggleViewMode() async {
    setState(() {
      _isGridMode = !_isGridMode;
    });
    await NoteStorage.saveViewMode(_isGridMode ? 'grid' : 'list');
  }

  Future<void> _saveAll() async {
    await NoteStorage.saveNotes(_notes);
  }

  Future<void> _togglePin(Note note) async {
    if (note.isDeleted || note.isArchived) {
      return;
    }
    final index = _notes.indexWhere((element) => element.id == note.id);
    if (index == -1) {
      return;
    }

    setState(() {
      _notes[index].isPinned = !_notes[index].isPinned;
      _notes[index].updatedAt = DateTime.now();
    });
    await _saveAll();
  }

  Future<void> _toggleArchive(Note note) async {
    if (note.isDeleted) {
      return;
    }
    final index = _notes.indexWhere((element) => element.id == note.id);
    if (index == -1) {
      return;
    }

    final archived = !_notes[index].isArchived;
    setState(() {
      _notes[index].isArchived = archived;
      _notes[index].isPinned = false;
      _notes[index].updatedAt = DateTime.now();
    });
    await _saveAll();

    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          archived ? 'Đã chuyển vào lưu trữ.' : 'Đã khôi phục khỏi lưu trữ.',
        ),
      ),
    );
  }

  Future<void> _moveToTrash(Note note) async {
    final index = _notes.indexWhere((element) => element.id == note.id);
    if (index == -1) {
      return;
    }

    setState(() {
      _notes[index].isDeleted = true;
      _notes[index].isArchived = false;
      _notes[index].isPinned = false;
      _notes[index].deletedAt = DateTime.now();
      _notes[index].updatedAt = DateTime.now();
    });
    await _saveAll();

    if (!mounted) {
      return;
    }

    final messenger = ScaffoldMessenger.of(context);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: const Text('Đã chuyển ghi chú vào thùng rác.'),
          action: SnackBarAction(
            label: 'Hoàn tác',
            onPressed: () async {
              await _restoreFromTrash(note, showSnackBar: false);
            },
          ),
        ),
      );
  }

  Future<void> _restoreFromTrash(Note note, {bool showSnackBar = true}) async {
    final index = _notes.indexWhere((element) => element.id == note.id);
    if (index == -1) {
      return;
    }

    setState(() {
      _notes[index].isDeleted = false;
      _notes[index].deletedAt = null;
      _notes[index].updatedAt = DateTime.now();
    });
    await _saveAll();

    if (!mounted || !showSnackBar) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Đã khôi phục ghi chú.')));
  }

  Future<void> _deletePermanently(Note note) async {
    final index = _notes.indexWhere((element) => element.id == note.id);
    if (index == -1) {
      return;
    }

    setState(() {
      _notes.removeAt(index);
    });
    await _saveAll();

    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Đã xóa vĩnh viễn ghi chú.')));
  }

  List<String> _availableTags() {
    final notes = _notes.where((note) {
      if (_bucket == NoteBucket.trash) {
        return note.isDeleted;
      }
      if (_bucket == NoteBucket.archived) {
        return !note.isDeleted && note.isArchived;
      }
      return !note.isDeleted && !note.isArchived;
    });

    final tags = <String>{};
    for (final note in notes) {
      tags.addAll(note.tags);
    }
    final list = tags.toList()..sort();
    return list;
  }

  List<Note> _visibleNotes() {
    final query = _searchController.text.trim().toLowerCase();

    final filtered = _notes.where((note) {
      final inBucket = switch (_bucket) {
        NoteBucket.notes => !note.isDeleted && !note.isArchived,
        NoteBucket.archived => !note.isDeleted && note.isArchived,
        NoteBucket.trash => note.isDeleted,
      };
      if (!inBucket) {
        return false;
      }

      if (_selectedTag != null && !note.tags.contains(_selectedTag)) {
        return false;
      }

      if (query.isEmpty) {
        return true;
      }

      final checklistText = note.checklistItems
          .map((item) => item.text)
          .join(' ');
      return note.title.toLowerCase().contains(query) ||
          note.content.toLowerCase().contains(query) ||
          note.tags.join(' ').toLowerCase().contains(query) ||
          checklistText.toLowerCase().contains(query);
    }).toList();

    filtered.sort((a, b) {
      if (_bucket == NoteBucket.notes && a.isPinned != b.isPinned) {
        return a.isPinned ? -1 : 1;
      }

      switch (_sort) {
        case NoteSort.updatedDesc:
          return b.updatedAt.compareTo(a.updatedAt);
        case NoteSort.updatedAsc:
          return a.updatedAt.compareTo(b.updatedAt);
        case NoteSort.titleAsc:
          return a.title.toLowerCase().compareTo(b.title.toLowerCase());
      }
    });

    return filtered;
  }

  Color _noteColor(BuildContext context, int colorIndex) {
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
    return colors[colorIndex % colors.length];
  }

  Future<void> _showDeleteDialog(Note note) async {
    final isTrash = _bucket == NoteBucket.trash;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(isTrash ? 'Xóa vĩnh viễn' : 'Chuyển vào thùng rác'),
          content: Text(
            isTrash
                ? 'Ghi chú sẽ bị xóa vĩnh viễn và không thể khôi phục.'
                : 'Bạn có chắc muốn chuyển ghi chú này vào thùng rác?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Hủy'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(isTrash ? 'Xóa luôn' : 'Chuyển vào thùng rác'),
            ),
          ],
        );
      },
    );

    if (confirm == true) {
      if (isTrash) {
        await _deletePermanently(note);
      } else {
        await _moveToTrash(note);
      }
    }
  }

  Future<void> _showCreateSheet() async {
    final type = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.sticky_note_2_outlined),
                title: const Text('Ghi chú văn bản'),
                subtitle: const Text(
                  'Phù hợp ghi ý tưởng, nhật ký, tài liệu ngắn.',
                ),
                onTap: () => Navigator.pop(context, 'note'),
              ),
              ListTile(
                leading: const Icon(Icons.checklist_rounded),
                title: const Text('Checklist / To-do'),
                subtitle: const Text('Phù hợp quản lý việc cần làm.'),
                onTap: () => Navigator.pop(context, 'checklist'),
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );

    if (!mounted || type == null) {
      return;
    }
    await _openEditor(startChecklist: type == 'checklist');
  }

  String _sortLabel(NoteSort sort) {
    switch (sort) {
      case NoteSort.updatedDesc:
        return 'Mới nhất';
      case NoteSort.updatedAsc:
        return 'Cũ nhất';
      case NoteSort.titleAsc:
        return 'Tên A-Z';
    }
  }

  @override
  Widget build(BuildContext context) {
    final notes = _visibleNotes();
    final availableTags = _availableTags();
    final colorScheme = Theme.of(context).colorScheme;

    if (_selectedTag != null && !availableTags.contains(_selectedTag)) {
      _selectedTag = null;
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Smart Note',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        actions: [
          IconButton(
            tooltip: _isGridMode ? 'Chế độ danh sách' : 'Chế độ lưới',
            onPressed: _toggleViewMode,
            icon: Icon(
              _isGridMode ? Icons.view_agenda_rounded : Icons.grid_view_rounded,
            ),
          ),
          PopupMenuButton<String>(
            tooltip: 'Tuỳ chọn',
            onSelected: (value) {
              if (value == 'sort_new') {
                setState(() => _sort = NoteSort.updatedDesc);
              } else if (value == 'sort_old') {
                setState(() => _sort = NoteSort.updatedAsc);
              } else if (value == 'sort_title') {
                setState(() => _sort = NoteSort.titleAsc);
              } else if (value == 'theme_system') {
                widget.onThemeModeChanged(AppThemeMode.system);
              } else if (value == 'theme_light') {
                widget.onThemeModeChanged(AppThemeMode.light);
              } else if (value == 'theme_dark') {
                widget.onThemeModeChanged(AppThemeMode.dark);
              }
            },
            itemBuilder: (context) {
              return [
                const PopupMenuItem<String>(
                  enabled: false,
                  child: Text('Sắp xếp'),
                ),
                PopupMenuItem<String>(
                  value: 'sort_new',
                  child: Row(
                    children: [
                      Icon(
                        _sort == NoteSort.updatedDesc
                            ? Icons.check
                            : Icons.circle_outlined,
                        size: 18,
                      ),
                      const SizedBox(width: 10),
                      const Text('Mới nhất'),
                    ],
                  ),
                ),
                PopupMenuItem<String>(
                  value: 'sort_old',
                  child: Row(
                    children: [
                      Icon(
                        _sort == NoteSort.updatedAsc
                            ? Icons.check
                            : Icons.circle_outlined,
                        size: 18,
                      ),
                      const SizedBox(width: 10),
                      const Text('Cũ nhất'),
                    ],
                  ),
                ),
                PopupMenuItem<String>(
                  value: 'sort_title',
                  child: Row(
                    children: [
                      Icon(
                        _sort == NoteSort.titleAsc
                            ? Icons.check
                            : Icons.circle_outlined,
                        size: 18,
                      ),
                      const SizedBox(width: 10),
                      const Text('Tên A-Z'),
                    ],
                  ),
                ),
                const PopupMenuDivider(),
                const PopupMenuItem<String>(
                  enabled: false,
                  child: Text('Giao diện'),
                ),
                PopupMenuItem<String>(
                  value: 'theme_system',
                  child: Row(
                    children: [
                      Icon(
                        widget.themeMode == AppThemeMode.system
                            ? Icons.check
                            : Icons.circle_outlined,
                        size: 18,
                      ),
                      const SizedBox(width: 10),
                      const Text('Theo hệ thống'),
                    ],
                  ),
                ),
                PopupMenuItem<String>(
                  value: 'theme_light',
                  child: Row(
                    children: [
                      Icon(
                        widget.themeMode == AppThemeMode.light
                            ? Icons.check
                            : Icons.circle_outlined,
                        size: 18,
                      ),
                      const SizedBox(width: 10),
                      const Text('Sáng'),
                    ],
                  ),
                ),
                PopupMenuItem<String>(
                  value: 'theme_dark',
                  child: Row(
                    children: [
                      Icon(
                        widget.themeMode == AppThemeMode.dark
                            ? Icons.check
                            : Icons.circle_outlined,
                        size: 18,
                      ),
                      const SizedBox(width: 10),
                      const Text('Tối'),
                    ],
                  ),
                ),
              ];
            },
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  child: SearchBar(
                    controller: _searchController,
                    hintText: 'Tìm kiếm ghi chú, tag, checklist...',
                    leading: const Icon(Icons.search_rounded),
                    trailing: _searchController.text.isEmpty
                        ? null
                        : [
                            IconButton(
                              onPressed: () {
                                _searchController.clear();
                                setState(() {});
                              },
                              icon: const Icon(Icons.close_rounded),
                            ),
                          ],
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: SegmentedButton<NoteBucket>(
                    segments: const [
                      ButtonSegment<NoteBucket>(
                        value: NoteBucket.notes,
                        icon: Icon(Icons.notes_rounded),
                        label: Text('Ghi chú'),
                      ),
                      ButtonSegment<NoteBucket>(
                        value: NoteBucket.archived,
                        icon: Icon(Icons.archive_rounded),
                        label: Text('Lưu trữ'),
                      ),
                      ButtonSegment<NoteBucket>(
                        value: NoteBucket.trash,
                        icon: Icon(Icons.delete_outline_rounded),
                        label: Text('Thùng rác'),
                      ),
                    ],
                    selected: {_bucket},
                    onSelectionChanged: (selected) {
                      setState(() {
                        _bucket = selected.first;
                        _selectedTag = null;
                      });
                    },
                  ),
                ),
                if (availableTags.isNotEmpty)
                  SizedBox(
                    height: 48,
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
                      scrollDirection: Axis.horizontal,
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: ChoiceChip(
                            label: const Text('Tất cả'),
                            selected: _selectedTag == null,
                            onSelected: (_) =>
                                setState(() => _selectedTag = null),
                          ),
                        ),
                        ...availableTags.map(
                          (tag) => Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            child: ChoiceChip(
                              label: Text('#$tag'),
                              selected: _selectedTag == tag,
                              onSelected: (_) =>
                                  setState(() => _selectedTag = tag),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                  child: Row(
                    children: [
                      Text(
                        '${notes.length} ghi chú · ${_sortLabel(_sort)}',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: notes.isEmpty
                      ? _EmptyState(
                          bucket: _bucket,
                          searching: _searchController.text.trim().isNotEmpty,
                        )
                      : RefreshIndicator(
                          onRefresh: _loadData,
                          child: _isGridMode
                              ? MasonryGridView.count(
                                  padding: const EdgeInsets.fromLTRB(
                                    12,
                                    8,
                                    12,
                                    100,
                                  ),
                                  crossAxisCount: 2,
                                  crossAxisSpacing: 12,
                                  mainAxisSpacing: 12,
                                  itemCount: notes.length,
                                  itemBuilder: (context, index) {
                                    final note = notes[index];
                                    return _NoteCard(
                                      note: note,
                                      isTrash: _bucket == NoteBucket.trash,
                                      color: _noteColor(
                                        context,
                                        note.colorIndex,
                                      ),
                                      onTap: () => _openEditor(note: note),
                                      onPinTap: () => _togglePin(note),
                                      onArchiveTap: () => _toggleArchive(note),
                                      onRestoreTap: () =>
                                          _restoreFromTrash(note),
                                      onDeleteTap: () =>
                                          _showDeleteDialog(note),
                                    );
                                  },
                                )
                              : ListView.separated(
                                  padding: const EdgeInsets.fromLTRB(
                                    12,
                                    8,
                                    12,
                                    100,
                                  ),
                                  itemCount: notes.length,
                                  separatorBuilder: (_, __) =>
                                      const SizedBox(height: 10),
                                  itemBuilder: (context, index) {
                                    final note = notes[index];
                                    return _NoteListTile(
                                      note: note,
                                      isTrash: _bucket == NoteBucket.trash,
                                      color: _noteColor(
                                        context,
                                        note.colorIndex,
                                      ),
                                      onTap: () => _openEditor(note: note),
                                      onPinTap: () => _togglePin(note),
                                      onArchiveTap: () => _toggleArchive(note),
                                      onRestoreTap: () =>
                                          _restoreFromTrash(note),
                                      onDeleteTap: () =>
                                          _showDeleteDialog(note),
                                    );
                                  },
                                ),
                        ),
                ),
              ],
            ),
      floatingActionButton: _bucket == NoteBucket.trash
          ? null
          : FloatingActionButton.extended(
              onPressed: _showCreateSheet,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Tạo mới'),
            ),
    );
  }
}

class _NoteCard extends StatelessWidget {
  const _NoteCard({
    required this.note,
    required this.isTrash,
    required this.color,
    required this.onTap,
    required this.onPinTap,
    required this.onArchiveTap,
    required this.onRestoreTap,
    required this.onDeleteTap,
  });

  final Note note;
  final bool isTrash;
  final Color color;
  final VoidCallback onTap;
  final VoidCallback onPinTap;
  final VoidCallback onArchiveTap;
  final VoidCallback onRestoreTap;
  final VoidCallback onDeleteTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final doneCount = note.checklistItems.where((item) => item.isDone).length;
    final previewBytes = _decodeAttachmentPreview(note);

    return Card(
      color: color,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      note.title.trim().isEmpty
                          ? 'Ghi chú không tiêu đề'
                          : note.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  PopupMenuButton<String>(
                    onSelected: (value) {
                      if (value == 'pin') {
                        onPinTap();
                      } else if (value == 'archive') {
                        onArchiveTap();
                      } else if (value == 'restore') {
                        onRestoreTap();
                      } else if (value == 'delete') {
                        onDeleteTap();
                      }
                    },
                    itemBuilder: (context) {
                      if (isTrash) {
                        return const [
                          PopupMenuItem<String>(
                            value: 'restore',
                            child: Text('Khôi phục'),
                          ),
                          PopupMenuItem<String>(
                            value: 'delete',
                            child: Text('Xóa vĩnh viễn'),
                          ),
                        ];
                      }

                      return [
                        PopupMenuItem<String>(
                          value: 'pin',
                          child: Text(
                            note.isPinned ? 'Bỏ ghim' : 'Ghim ghi chú',
                          ),
                        ),
                        PopupMenuItem<String>(
                          value: 'archive',
                          child: Text(
                            note.isArchived ? 'Bỏ lưu trữ' : 'Lưu trữ',
                          ),
                        ),
                        const PopupMenuItem<String>(
                          value: 'delete',
                          child: Text('Chuyển thùng rác'),
                        ),
                      ];
                    },
                  ),
                ],
              ),
              if (note.isChecklist && note.checklistItems.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  '$doneCount/${note.checklistItems.length} việc đã hoàn thành',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 6),
                ...note.checklistItems
                    .take(3)
                    .map(
                      (item) => Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Row(
                          children: [
                            Icon(
                              item.isDone
                                  ? Icons.check_circle_rounded
                                  : Icons.radio_button_unchecked_rounded,
                              size: 14,
                              color: item.isDone
                                  ? theme.colorScheme.primary
                                  : theme.colorScheme.onSurfaceVariant,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                item.text,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
              ] else if (note.content.trim().isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  note.content,
                  maxLines: 6,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    height: 1.35,
                  ),
                ),
              ],
              if (previewBytes != null) ...[
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.memory(
                    previewBytes,
                    width: double.infinity,
                    height: 120,
                    fit: BoxFit.cover,
                  ),
                ),
              ],
              if (note.tags.isNotEmpty) ...[
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: note.tags
                      .take(3)
                      .map(
                        (tag) => Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primaryContainer
                                .withValues(alpha: 0.55),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            '#$tag',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onPrimaryContainer,
                            ),
                          ),
                        ),
                      )
                      .toList(),
                ),
              ],
              if (note.attachments.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  '${note.attachments.length} tệp đính kèm',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
              const SizedBox(height: 10),
              Row(
                children: [
                  if (note.isPinned)
                    Icon(
                      Icons.push_pin_rounded,
                      size: 16,
                      color: theme.colorScheme.primary,
                    ),
                  if (note.isPinned) const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      _formatDate(note.updatedAt),
                      textAlign: TextAlign.right,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NoteListTile extends StatelessWidget {
  const _NoteListTile({
    required this.note,
    required this.isTrash,
    required this.color,
    required this.onTap,
    required this.onPinTap,
    required this.onArchiveTap,
    required this.onRestoreTap,
    required this.onDeleteTap,
  });

  final Note note;
  final bool isTrash;
  final Color color;
  final VoidCallback onTap;
  final VoidCallback onPinTap;
  final VoidCallback onArchiveTap;
  final VoidCallback onRestoreTap;
  final VoidCallback onDeleteTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final doneCount = note.checklistItems.where((item) => item.isDone).length;
    final previewBytes = _decodeAttachmentPreview(note);
    final subtitleText = note.isChecklist
        ? '$doneCount/${note.checklistItems.length} việc đã hoàn thành'
        : (note.content.trim().isEmpty ? 'Không có nội dung' : note.content);

    return Card(
      color: color,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (previewBytes != null)
                Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Image.memory(
                      previewBytes,
                      width: 72,
                      height: 72,
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      note.title.trim().isEmpty
                          ? 'Ghi chú không tiêu đề'
                          : note.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitleText,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (note.attachments.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        '${note.attachments.length} tệp đính kèm',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Column(
                children: [
                  if (note.isPinned)
                    Icon(
                      Icons.push_pin_rounded,
                      color: theme.colorScheme.primary,
                    ),
                  PopupMenuButton<String>(
                    onSelected: (value) {
                      if (value == 'pin') {
                        onPinTap();
                      } else if (value == 'archive') {
                        onArchiveTap();
                      } else if (value == 'restore') {
                        onRestoreTap();
                      } else if (value == 'delete') {
                        onDeleteTap();
                      }
                    },
                    itemBuilder: (context) {
                      if (isTrash) {
                        return const [
                          PopupMenuItem<String>(
                            value: 'restore',
                            child: Text('Khôi phục'),
                          ),
                          PopupMenuItem<String>(
                            value: 'delete',
                            child: Text('Xóa vĩnh viễn'),
                          ),
                        ];
                      }

                      return [
                        PopupMenuItem<String>(
                          value: 'pin',
                          child: Text(
                            note.isPinned ? 'Bỏ ghim' : 'Ghim ghi chú',
                          ),
                        ),
                        PopupMenuItem<String>(
                          value: 'archive',
                          child: Text(
                            note.isArchived ? 'Bỏ lưu trữ' : 'Lưu trữ',
                          ),
                        ),
                        const PopupMenuItem<String>(
                          value: 'delete',
                          child: Text('Chuyển thùng rác'),
                        ),
                      ];
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Uint8List? _decodeAttachmentPreview(Note note) {
  if (note.attachments.isEmpty) {
    return null;
  }

  final first = note.attachments.first.base64Data;
  try {
    return base64Decode(first);
  } catch (_) {
    return null;
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.bucket, required this.searching});

  final NoteBucket bucket;
  final bool searching;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    String title;
    IconData icon;

    if (searching) {
      title = 'Không có ghi chú phù hợp';
      icon = Icons.search_off_rounded;
    } else {
      switch (bucket) {
        case NoteBucket.notes:
          title = 'Tạo ghi chú đầu tiên của bạn';
          icon = Icons.edit_note_rounded;
        case NoteBucket.archived:
          title = 'Chưa có ghi chú lưu trữ';
          icon = Icons.archive_outlined;
        case NoteBucket.trash:
          title = 'Thùng rác đang trống';
          icon = Icons.delete_outline_rounded;
      }
    }

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(
              color: colorScheme.primaryContainer.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(24),
            ),
            child: Icon(icon, size: 44, color: colorScheme.onPrimaryContainer),
          ),
          const SizedBox(height: 16),
          Text(title, style: Theme.of(context).textTheme.titleMedium),
        ],
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
