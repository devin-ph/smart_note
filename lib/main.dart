import 'package:flutter/material.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'dart:convert';
import 'dart:async';

import 'note.dart';
import 'note_edit_screen.dart';
import 'note_storage.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await _initializeFirebase();
  runApp(const SmartNoteApp());
}

Future<void> _initializeFirebase() async {
  try {
    if (kIsWeb) {
      final webOptions = _firebaseOptionsFromEnvironment();
      if (webOptions == null) {
        debugPrint(
          'Firebase Web chưa có cấu hình. App sẽ chạy local-only. '
          'Bạn có thể chạy flutterfire configure hoặc truyền --dart-define.',
        );
        return;
      }
      await Firebase.initializeApp(options: webOptions);
    } else {
      await Firebase.initializeApp();
    }

    if (FirebaseAuth.instance.currentUser == null) {
      await FirebaseAuth.instance.signInAnonymously();
    }
  } catch (error) {
    debugPrint('Firebase khởi tạo thất bại, fallback local-only: $error');
    debugPrint(
      'Chạy `flutterfire configure` để liên kết Firebase project cho app.',
    );
  }
}

FirebaseOptions? _firebaseOptionsFromEnvironment() {
  const apiKey = String.fromEnvironment('FIREBASE_WEB_API_KEY');
  const appId = String.fromEnvironment('FIREBASE_WEB_APP_ID');
  const messagingSenderId = String.fromEnvironment(
    'FIREBASE_WEB_MESSAGING_SENDER_ID',
  );
  const projectId = String.fromEnvironment('FIREBASE_WEB_PROJECT_ID');
  const authDomain = String.fromEnvironment('FIREBASE_WEB_AUTH_DOMAIN');
  const storageBucket = String.fromEnvironment('FIREBASE_WEB_STORAGE_BUCKET');
  const measurementId = String.fromEnvironment('FIREBASE_WEB_MEASUREMENT_ID');

  if (apiKey.isEmpty ||
      appId.isEmpty ||
      messagingSenderId.isEmpty ||
      projectId.isEmpty) {
    return null;
  }

  return FirebaseOptions(
    apiKey: apiKey,
    appId: appId,
    messagingSenderId: messagingSenderId,
    projectId: projectId,
    authDomain: authDomain.isEmpty ? null : authDomain,
    storageBucket: storageBucket.isEmpty ? null : storageBucket,
    measurementId: measurementId.isEmpty ? null : measurementId,
  );
}

enum AppThemeMode { system, light, dark }

enum NoteSort { updatedDesc, updatedAsc, titleAsc }

enum NoteBucket { notes, trash }

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
  StreamSubscription<List<Note>>? _notesSubscription;

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
    _bindCloudSync();
  }

  @override
  void dispose() {
    _notesSubscription?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _bindCloudSync() {
    _notesSubscription?.cancel();
    _notesSubscription = NoteStorage.watchNotes().listen((cloudNotes) async {
      if (!mounted || cloudNotes.isEmpty) {
        return;
      }

      final localById = {for (final note in _notes) note.id: note};
      for (final cloudNote in cloudNotes) {
        final local = localById[cloudNote.id];
        if (local == null || cloudNote.updatedAt.isAfter(local.updatedAt)) {
          localById[cloudNote.id] = cloudNote;
        }
      }

      final merged = localById.values.toList()
        ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

      if (!mounted) {
        return;
      }

      setState(() {
        _notes = merged;
      });
    });
  }

  Future<void> _loadData() async {
    final notes = await NoteStorage.loadNotes();
    final viewMode = await NoteStorage.loadViewMode();
    var hasArchivedNotes = false;

    final normalizedNotes = notes.map((note) {
      if (!note.isArchived) {
        return note;
      }

      hasArchivedNotes = true;
      return Note(
        id: note.id,
        title: note.title,
        content: note.content,
        createdAt: note.createdAt,
        updatedAt: note.updatedAt,
        isPinned: note.isPinned,
        isArchived: false,
        isDeleted: note.isDeleted,
        colorIndex: note.colorIndex,
        tags: List<String>.from(note.tags),
        isChecklist: note.isChecklist,
        checklistItems: List<ChecklistItem>.from(note.checklistItems),
        attachments: List<NoteAttachment>.from(note.attachments),
        deletedAt: note.deletedAt,
      );
    }).toList();

    if (hasArchivedNotes) {
      await NoteStorage.saveNotes(normalizedNotes);
    }

    if (!mounted) {
      return;
    }

    setState(() {
      _notes = normalizedNotes;
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
    if (note.isDeleted) {
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
      return _bucket == NoteBucket.trash ? note.isDeleted : !note.isDeleted;
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
        NoteBucket.notes => !note.isDeleted,
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
    required this.onRestoreTap,
    required this.onDeleteTap,
  });

  final Note note;
  final bool isTrash;
  final Color color;
  final VoidCallback onTap;
  final VoidCallback onPinTap;
  final VoidCallback onRestoreTap;
  final VoidCallback onDeleteTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final previewText = _buildTextPreviewContent(note);
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
                ..._buildChecklistPreviewRows(note, theme),
              ] else if (previewText.isNotEmpty) ...[
                const SizedBox(height: 8),
                _ThreeLinePreviewText(
                  text: previewText,
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
    required this.onRestoreTap,
    required this.onDeleteTap,
  });

  final Note note;
  final bool isTrash;
  final Color color;
  final VoidCallback onTap;
  final VoidCallback onPinTap;
  final VoidCallback onRestoreTap;
  final VoidCallback onDeleteTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final previewBytes = _decodeAttachmentPreview(note);
    final subtitleText = _buildTextPreviewContent(note);

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
                    if (note.isChecklist && note.checklistItems.isNotEmpty)
                      ..._buildChecklistPreviewRows(note, theme)
                    else
                      _ThreeLinePreviewText(
                        text: subtitleText,
                        style: theme.textTheme.bodyMedium,
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

class _ThreeLinePreviewText extends StatelessWidget {
  const _ThreeLinePreviewText({required this.text, this.style});

  final String text;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final value = text.trimRight();
    if (value.isEmpty) {
      return const SizedBox.shrink();
    }

    final direction = Directionality.of(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth;

        final fullPainter = TextPainter(
          text: TextSpan(text: value, style: style),
          textDirection: direction,
          maxLines: 3,
        )..layout(maxWidth: maxWidth);

        if (!fullPainter.didExceedMaxLines) {
          return Text(
            value,
            maxLines: 3,
            overflow: TextOverflow.clip,
            style: style,
          );
        }

        var low = 0;
        var high = value.length;
        var best = '...';

        while (low <= high) {
          final mid = (low + high) ~/ 2;
          final candidate = '${value.substring(0, mid).trimRight()}...';
          final painter = TextPainter(
            text: TextSpan(text: candidate, style: style),
            textDirection: direction,
            maxLines: 3,
          )..layout(maxWidth: maxWidth);

          if (painter.didExceedMaxLines) {
            high = mid - 1;
          } else {
            best = candidate;
            low = mid + 1;
          }
        }

        return Text(
          best,
          maxLines: 3,
          overflow: TextOverflow.clip,
          style: style,
        );
      },
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

String _buildTextPreviewContent(Note note) {
  final content = note.content.trim();
  if (content.isNotEmpty) {
    return content;
  }

  return 'Không có nội dung';
}

List<Widget> _buildChecklistPreviewRows(Note note, ThemeData theme) {
  final items = note.checklistItems.take(3).toList();
  final hasMore = note.checklistItems.length > 3;

  return List.generate(items.length, (index) {
    final item = items[index];
    final isLastVisible = index == items.length - 1;
    final text = isLastVisible && hasMore ? '${item.text}...' : item.text;

    return Padding(
      padding: EdgeInsets.only(bottom: index == items.length - 1 ? 0 : 4),
      child: Row(
        children: [
          Icon(
            item.isDone
                ? Icons.check_box_rounded
                : Icons.check_box_outline_blank_rounded,
            size: 14,
            color: item.isDone
                ? theme.colorScheme.primary
                : theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  });
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
