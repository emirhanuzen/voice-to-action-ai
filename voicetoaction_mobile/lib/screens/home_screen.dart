import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/api_service.dart';
import 'profile_screen.dart';

// ─── Kayıt modeli ─────────────────────────────────────────────────────────────
class _RecordItem {
  _RecordItem({
    required this.fileName,
    required this.category,
    required this.transcript,
  });

  final String fileName;
  final String category;
  final String transcript;
}

// ─── Görev modeli ─────────────────────────────────────────────────────────────
class _TaskItem {
  _TaskItem({
    this.id,
    required this.title,
    this.dueDate,
    this.status = 'pending',
  });

  factory _TaskItem.fromJson(Map<String, dynamic> json) => _TaskItem(
        id: json['id'] as int?,
        // Transkripsiyon API'si 'task_title', DB API'si 'title' döndürür.
        title: (json['title'] as String?) ??
            (json['task_title'] as String?) ??
            'Görev',
        dueDate: json['due_date'] as String?,
        status: (json['status'] as String?) ?? 'pending',
      );

  final int? id;
  final String title;
  final String? dueDate;
  final String status;
}

// ─── Kategori sabitleri ───────────────────────────────────────────────────────
class _Cat {
  static const List<Map<String, dynamic>> all = <Map<String, dynamic>>[
    <String, dynamic>{
      'label': 'Eğitim',
      'icon': Icons.school_rounded,
      'color': Color(0xFF3B82F6),
      'bg': Color(0xFFDBEAFE),
    },
    <String, dynamic>{
      'label': 'Toplantı',
      'icon': Icons.work_rounded,
      'color': Color(0xFFA855F7),
      'bg': Color(0xFFF3E8FF),
    },
    <String, dynamic>{
      'label': 'Röportaj',
      'icon': Icons.keyboard_voice_rounded,
      'color': Color(0xFFF59E0B),
      'bg': Color(0xFFFEF3C7),
    },
    <String, dynamic>{
      'label': 'Diğer',
      'icon': Icons.folder_rounded,
      'color': Color(0xFF64748B),
      'bg': Color(0xFFF1F5F9),
    },
  ];

  static Color color(String label) {
    final Map<String, dynamic>? c =
        all.where((Map<String, dynamic> m) => m['label'] == label).firstOrNull;
    return (c?['color'] as Color?) ?? const Color(0xFF2563EB);
  }

  static Color bg(String label) {
    final Map<String, dynamic>? c =
        all.where((Map<String, dynamic> m) => m['label'] == label).firstOrNull;
    return (c?['bg'] as Color?) ?? const Color(0xFFDBEAFE);
  }

  static IconData icon(String label) {
    final Map<String, dynamic>? c =
        all.where((Map<String, dynamic> m) => m['label'] == label).firstOrNull;
    return (c?['icon'] as IconData?) ?? Icons.description_outlined;
  }
}

// ─── Ana widget ───────────────────────────────────────────────────────────────
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  static const String routeName = '/home';

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final ApiService _apiService = ApiService();

  int _selectedBottomIndex = 0;
  bool _isLoading = false;
  String _userName = 'Kullanici';
  String _userEmail = 'kullanici@ornek.com';

  String _currentFileName = '';
  String _currentCategory = '';
  final List<_RecordItem> _recentItems = <_RecordItem>[];
  final List<_TaskItem> _tasks = <_TaskItem>[];
  bool _isInitialLoading = false;

  @override
  void initState() {
    super.initState();
    _loadUserIdentity();
    _loadInitialData();
  }

  // ── Identity ──────────────────────────────────────────────────────────────
  Future<void> _loadUserIdentity() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String email = prefs.getString('user_email') ?? 'kullanici@ornek.com';
    final String name = prefs.getString('user_name') ?? 'Kullanici';
    if (!mounted) return;
    setState(() {
      _userEmail = email;
      _userName = name.trim().isEmpty ? email : name;
    });
  }

  // ── Backend'den ilk veri yükü (kayıtlar + görevler) ──────────────────────
  Future<void> _loadInitialData() async {
    print('[HomeScreen] _loadInitialData başladı.');
    setState(() => _isInitialLoading = true);

    final List<Map<String, dynamic>> records = await _apiService.getRecords();
    final List<Map<String, dynamic>> tasks = await _apiService.getTasks();

    print('[HomeScreen] Backend\'den ${records.length} kayıt, '
        '${tasks.length} görev alındı.');

    if (!mounted) return;

    setState(() {
      _isInitialLoading = false;

      _recentItems
        ..clear()
        ..addAll(
          records.map(
            (Map<String, dynamic> r) => _RecordItem(
              fileName: (r['file_name'] as String?) ?? 'Kayıt',
              category: (r['category'] as String?) ?? 'Diğer',
              transcript: (r['transcript'] as String?) ?? '',
            ),
          ),
        );

      _tasks
        ..clear()
        ..addAll(tasks.map(_TaskItem.fromJson));
    });

    print('[HomeScreen] Liste güncellendi: '
        '${_recentItems.length} kayıt, ${_tasks.length} görev.');
  }

  String _buildInitials(String name) {
    final List<String> parts = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((String p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) return 'KU';
    if (parts.length == 1) {
      final String s = parts.first.toUpperCase();
      return s.length >= 2 ? s.substring(0, 2) : '$s$s';
    }
    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }

  // ── FAB → seçenek sheet'i ─────────────────────────────────────────────────
  void _showFabOptions() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (BuildContext ctx) {
        return _SheetContainer(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _sheetHandle(),
              const SizedBox(height: 16),
              Text(
                'Ne yapmak istersin?',
                style: GoogleFonts.inter(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF1E293B),
                ),
              ),
              const SizedBox(height: 16),
              _FabOptionTile(
                icon: Icons.mic_rounded,
                iconBg: const Color(0xFFDBEAFE),
                iconColor: const Color(0xFF2563EB),
                title: '🎤  Ses Kaydet',
                subtitle: 'Mikrofon ile yeni kayıt başlat',
                onTap: () {
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      content: Text(
                        'Mikrofon kayıt modülü İP-6 iş paketinde aktif edilecektir.',
                        style: GoogleFonts.inter(fontWeight: FontWeight.w600),
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 10),
              _FabOptionTile(
                icon: Icons.audio_file_rounded,
                iconBg: const Color(0xFFF3E8FF),
                iconColor: const Color(0xFFA855F7),
                title: '📁  Ses Dosyası Seç',
                subtitle: 'Cihazdan ses/video dosyası yükle',
                onTap: () {
                  Navigator.pop(ctx);
                  _pickAndTranscribe();
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  // ── Kategori sheet ────────────────────────────────────────────────────────
  Future<String?> _showCategorySheet() async {
    return showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (BuildContext ctx) {
        return _SheetContainer(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _sheetHandle(),
              const SizedBox(height: 16),
              Text(
                'Kategori Seç',
                style: GoogleFonts.inter(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF1E293B),
                ),
              ),
              Text(
                'Bu kaydı hangi kategoriye eklemek istersin?',
                style: GoogleFonts.inter(
                    fontSize: 13, color: const Color(0xFF64748B)),
              ),
              const SizedBox(height: 16),
              ..._Cat.all.map((Map<String, dynamic> cat) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: () => Navigator.pop(ctx, cat['label'] as String),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 13),
                      decoration: BoxDecoration(
                        color: cat['bg'] as Color,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Row(
                        children: <Widget>[
                          Icon(cat['icon'] as IconData,
                              color: cat['color'] as Color, size: 20),
                          const SizedBox(width: 12),
                          Text(
                            cat['label'] as String,
                            style: GoogleFonts.inter(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: const Color(0xFF1E293B),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }),
            ],
          ),
        );
      },
    );
  }

  // ── Dosya seç + transkripsiyon ───────────────────────────────────────────
  Future<void> _pickAndTranscribe() async {
    if (_isLoading) return;

    final FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.audio,
    );
    if (result == null || result.files.single.path == null) return;

    final String pickedFileName = result.files.single.name.isNotEmpty
        ? result.files.single.name
        : 'Medya Dosyası';

    final String? chosenCategory = await _showCategorySheet();
    if (chosenCategory == null) return;

    setState(() {
      _isLoading = true;
      _currentFileName = pickedFileName;
      _currentCategory = chosenCategory;
    });

    print('[HomeScreen] Transkripsiyon başlatıldı: '
        'dosya=$pickedFileName kategori=$chosenCategory');

    final Map<String, dynamic>? transcribeResult =
        await _apiService.uploadMediaAndTranscribe(
      File(result.files.single.path!),
      category: chosenCategory,
    );

    print('[HomeScreen] Transkripsiyon yanıtı: $transcribeResult');

    if (!mounted) return;

    final String? text = transcribeResult?['text'] as String?;
    final List<dynamic> newTasksRaw =
        (transcribeResult?['tasks'] as List<dynamic>?) ?? <dynamic>[];

    print('[HomeScreen] Metin uzunluğu: ${text?.length ?? 0}, '
        'yeni görev sayısı: ${newTasksRaw.length}');

    setState(() {
      _isLoading = false;
      if (text != null && text.trim().isNotEmpty) {
        _recentItems.insert(
          0,
          _RecordItem(
            fileName: pickedFileName,
            category: chosenCategory,
            transcript: text,
          ),
        );
        for (final dynamic t in newTasksRaw) {
          if (t is Map<String, dynamic>) {
            _tasks.insert(0, _TaskItem.fromJson(t));
          }
        }
        print('[HomeScreen] setState tamamlandı: '
            'toplam ${_recentItems.length} kayıt, ${_tasks.length} görev.');
      } else {
        print('[HomeScreen] UYARI: Transkripsiyon boş veya null döndü.');
      }
    });

    if (text != null && text.trim().isNotEmpty) {
      _showTranscriptSheet(fileName: pickedFileName, text: text);
      return;
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Transkripsiyon sonucu alinamadi.')),
      );
    }
  }

  // ── Transkript sheet ──────────────────────────────────────────────────────
  void _showTranscriptSheet({required String fileName, required String text}) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (BuildContext ctx) {
        final double maxH = MediaQuery.of(ctx).size.height * 0.75;
        return Container(
          constraints: BoxConstraints(maxHeight: maxH),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.only(top: 14),
                  child: Center(child: _sheetHandle()),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
                  child: Text(
                    fileName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                      color: const Color(0xFF1E293B),
                    ),
                  ),
                ),
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
                    child: Text(
                      text,
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        height: 1.6,
                        color: const Color(0xFF334155),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ── Nav ───────────────────────────────────────────────────────────────────
  void _onBottomNavTap(int index) {
    if (index == 3) {
      Navigator.pushNamed(context, ProfileScreen.routeName);
      return;
    }
    setState(() => _selectedBottomIndex = index);
  }

  // ── Build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final String displayName =
        _userName.trim().isEmpty ? _userEmail : _userName;

    Widget body;
    switch (_selectedBottomIndex) {
      case 1:
        body = _TasksPage(tasks: _tasks, isLoading: _isInitialLoading);
      case 2:
        body = _RecordsPage(
          recentItems: _recentItems,
          onRecordTap: (String fn, String tx) =>
              _showTranscriptSheet(fileName: fn, text: tx),
        );
      default:
        body = _HomePage(
          displayName: displayName,
          initials: _buildInitials(displayName),
          onProfileTap: () =>
              Navigator.pushNamed(context, ProfileScreen.routeName),
          isLoading: _isLoading,
          currentFileName: _currentFileName,
          currentCategory: _currentCategory,
          recentItems: _recentItems,
          onUploadTap: _showFabOptions,
          onRecordTap: (String fn, String tx) =>
              _showTranscriptSheet(fileName: fn, text: tx),
        );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      floatingActionButton: GestureDetector(
        onTap: _showFabOptions,
        child: Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            color: const Color(0xFF2563EB),
            borderRadius: BorderRadius.circular(32),
            border: Border.all(color: Colors.white, width: 4),
            boxShadow: const <BoxShadow>[
              BoxShadow(
                color: Color(0x552563EB),
                blurRadius: 18,
                offset: Offset(0, 8),
              ),
            ],
          ),
          child: const Icon(Icons.mic_rounded, color: Colors.white, size: 30),
        ),
      ),
      bottomNavigationBar: _BottomNavBar(
        selectedIndex: _selectedBottomIndex,
        onTap: _onBottomNavTap,
      ),
      body: SafeArea(child: body),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// SAYFA: Ana Sayfa
// ═══════════════════════════════════════════════════════════════════════════════
class _HomePage extends StatelessWidget {
  const _HomePage({
    required this.displayName,
    required this.initials,
    required this.onProfileTap,
    required this.isLoading,
    required this.currentFileName,
    required this.currentCategory,
    required this.recentItems,
    required this.onUploadTap,
    required this.onRecordTap,
  });

  final String displayName;
  final String initials;
  final VoidCallback onProfileTap;
  final bool isLoading;
  final String currentFileName;
  final String currentCategory;
  final List<_RecordItem> recentItems;
  final VoidCallback onUploadTap;
  final void Function(String fileName, String transcript) onRecordTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        _Header(
          displayName: displayName,
          initials: initials,
          onProfileTap: onProfileTap,
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 110),
            children: <Widget>[
              _QuickActionCard(onTap: onUploadTap),
              const SizedBox(height: 22),
              _CategorySection(
                recentItems: recentItems,
                onRecordTap: onRecordTap,
              ),
              const SizedBox(height: 22),
              const _UrgentTaskCard(),
              const SizedBox(height: 22),
              _RecentSection(
                isLoading: isLoading,
                currentFileName: currentFileName,
                currentCategory: currentCategory,
                recentItems: recentItems,
                onRecordTap: onRecordTap,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// SAYFA: Görevler
// ═══════════════════════════════════════════════════════════════════════════════
class _TasksPage extends StatelessWidget {
  const _TasksPage({required this.tasks, this.isLoading = false});

  final List<_TaskItem> tasks;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFF4F46E5)),
      );
    }

    if (tasks.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: const Color(0xFFEEF2FF),
                borderRadius: BorderRadius.circular(36),
              ),
              child: const Icon(Icons.checklist_rounded,
                  size: 36, color: Color(0xFF4F46E5)),
            ),
            const SizedBox(height: 16),
            Text(
              'Yaklaşan Görev Bulunmuyor',
              style: GoogleFonts.inter(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: const Color(0xFF1E293B),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Ses kayıtlarından AI otomatik\ngörev çıkardığında burada görünecek.',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: 13,
                color: const Color(0xFF64748B),
                height: 1.5,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 110),
      itemCount: tasks.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (BuildContext context, int i) => _TaskCard(task: tasks[i]),
    );
  }
}

// ─── Görev kartı ──────────────────────────────────────────────────────────────
class _TaskCard extends StatelessWidget {
  const _TaskCard({required this.task});

  final _TaskItem task;

  @override
  Widget build(BuildContext context) {
    // Due date parse & format
    String dueDateLabel = '';
    bool isOverdue = false;
    if (task.dueDate != null && task.dueDate!.isNotEmpty) {
      try {
        final DateTime dt = DateTime.parse(task.dueDate!);
        isOverdue = dt.isBefore(DateTime.now());
        dueDateLabel = '${dt.day.toString().padLeft(2, '0')}.'
            '${dt.month.toString().padLeft(2, '0')}.'
            '${dt.year}';
      } catch (_) {
        dueDateLabel = task.dueDate!;
      }
    }

    final bool isDone = task.status == 'done';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFF1F5F9)),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x0A0F172A),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: isDone
                  ? const Color(0xFFDCFCE7)
                  : const Color(0xFFEEF2FF),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Icon(
              isDone
                  ? Icons.check_circle_outline_rounded
                  : Icons.radio_button_unchecked_rounded,
              color:
                  isDone ? const Color(0xFF16A34A) : const Color(0xFF4F46E5),
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  task.title,
                  style: GoogleFonts.inter(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: isDone
                        ? const Color(0xFF94A3B8)
                        : const Color(0xFF1E293B),
                    height: 1.35,
                    decoration: isDone
                        ? TextDecoration.lineThrough
                        : TextDecoration.none,
                  ),
                ),
                if (dueDateLabel.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 6),
                  Row(
                    children: <Widget>[
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: isOverdue
                              ? const Color(0xFFFEF2F2)
                              : const Color(0xFFEEF2FF),
                          borderRadius: BorderRadius.circular(7),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            Icon(
                              Icons.calendar_today_rounded,
                              size: 9,
                              color: isOverdue
                                  ? const Color(0xFFDC2626)
                                  : const Color(0xFF4F46E5),
                            ),
                            const SizedBox(width: 3),
                            Text(
                              dueDateLabel,
                              style: GoogleFonts.inter(
                                color: isOverdue
                                    ? const Color(0xFFDC2626)
                                    : const Color(0xFF4F46E5),
                                fontWeight: FontWeight.w700,
                                fontSize: 10,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 6),
                      const Icon(Icons.smart_toy_outlined,
                          size: 11, color: Color(0xFF64748B)),
                      const SizedBox(width: 3),
                      Text(
                        'AI tespit etti',
                        style: GoogleFonts.inter(
                          color: const Color(0xFF64748B),
                          fontSize: 10,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// SAYFA: Kayıtlar
// ═══════════════════════════════════════════════════════════════════════════════
class _RecordsPage extends StatelessWidget {
  const _RecordsPage({
    required this.recentItems,
    required this.onRecordTap,
  });

  final List<_RecordItem> recentItems;
  final void Function(String fileName, String transcript) onRecordTap;

  @override
  Widget build(BuildContext context) {
    if (recentItems.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: const Color(0xFFF3E8FF),
                borderRadius: BorderRadius.circular(36),
              ),
              child: const Icon(Icons.folder_open_rounded,
                  size: 36, color: Color(0xFFA855F7)),
            ),
            const SizedBox(height: 16),
            Text(
              'Henüz Bir Kayıt Bulunmuyor',
              style: GoogleFonts.inter(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: const Color(0xFF1E293B),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Mikrofon butonuna basarak ilk\nkaydını oluşturmaya başla.',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: 13,
                color: const Color(0xFF64748B),
                height: 1.5,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 110),
      itemCount: recentItems.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (BuildContext context, int i) {
        final _RecordItem item = recentItems[i];
        return _DynamicRecordCard(
          item: item,
          onTap: () => onRecordTap(item.fileName, item.transcript),
        );
      },
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// YARDIMCI: drag handle
// ═══════════════════════════════════════════════════════════════════════════════
Widget _sheetHandle() => Container(
      width: 42,
      height: 4,
      decoration: BoxDecoration(
        color: const Color(0xFFCBD5E1),
        borderRadius: BorderRadius.circular(3),
      ),
    );

// ─── Sheet sarmalayıcı ────────────────────────────────────────────────────────
class _SheetContainer extends StatelessWidget {
  const _SheetContainer({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
      child: SafeArea(top: false, child: child),
    );
  }
}

// ─── FAB seçenek tile ─────────────────────────────────────────────────────────
class _FabOptionTile extends StatelessWidget {
  const _FabOptionTile({
    required this.icon,
    required this.iconBg,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final Color iconBg;
  final Color iconColor;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: iconBg.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: iconBg),
        ),
        child: Row(
          children: <Widget>[
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: iconBg,
                borderRadius: BorderRadius.circular(22),
              ),
              child: Icon(icon, color: iconColor, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    title,
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF1E293B),
                    ),
                  ),
                  Text(
                    subtitle,
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      color: const Color(0xFF64748B),
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded,
                color: Color(0xFFCBD5E1), size: 20),
          ],
        ),
      ),
    );
  }
}

// ─── Header ───────────────────────────────────────────────────────────────────
class _Header extends StatelessWidget {
  const _Header({
    required this.displayName,
    required this.initials,
    required this.onProfileTap,
  });

  final String displayName;
  final String initials;
  final VoidCallback onProfileTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'İyi Günler,',
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    color: const Color(0xFF64748B),
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.1,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '$displayName 👋',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    fontSize: 22,
                    color: const Color(0xFF1E293B),
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Row(
            children: <Widget>[
              Stack(
                clipBehavior: Clip.none,
                children: <Widget>[
                  const Icon(Icons.notifications_none_rounded,
                      color: Color(0xFF94A3B8), size: 24),
                  Positioned(
                    right: -1,
                    top: -2,
                    child: Container(
                      width: 12,
                      height: 12,
                      decoration: const BoxDecoration(
                        color: Color(0xFFEF4444),
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text(
                          '2',
                          style: GoogleFonts.inter(
                            fontSize: 8,
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 12),
              GestureDetector(
                onTap: onProfileTap,
                child: Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: const Color(0xFFDBEAFE),
                    borderRadius: BorderRadius.circular(19),
                    border: Border.all(color: const Color(0xFFBFDBFE)),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    initials,
                    style: GoogleFonts.inter(
                      color: const Color(0xFF2563EB),
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── Quick Action Card ────────────────────────────────────────────────────────
class _QuickActionCard extends StatelessWidget {
  const _QuickActionCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFFEEF2FF),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE0E7FF)),
          boxShadow: const <BoxShadow>[
            BoxShadow(
              color: Color(0x140F172A),
              blurRadius: 10,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: <Widget>[
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: const Color(0xFFE0E7FF),
                borderRadius: BorderRadius.circular(21),
              ),
              child: const Icon(Icons.video_file_rounded,
                  color: Color(0xFF4F46E5), size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    'Videoyu Sese Çevir',
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF1E293B),
                    ),
                  ),
                  Text(
                    'FFMPEG ile analiz et',
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: const Color(0xFF64748B),
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: Color(0xFFA5B4FC)),
          ],
        ),
      ),
    );
  }
}

// ─── Kategoriler ──────────────────────────────────────────────────────────────
class _CategorySection extends StatelessWidget {
  const _CategorySection({
    required this.recentItems,
    required this.onRecordTap,
  });

  final List<_RecordItem> recentItems;
  final void Function(String fileName, String transcript) onRecordTap;

  // Solid background rengi (kart zemin)
  static Color _solidBg(String label) {
    switch (label) {
      case 'Eğitim':
        return const Color(0xFF3B82F6);
      case 'Toplantı':
        return const Color(0xFFA855F7);
      case 'Röportaj':
        return const Color(0xFFF59E0B);
      default:
        return const Color(0xFF64748B);
    }
  }

  // Açık ikon rengi (kart üzerindeki ikon)
  static Color _lightIcon(String label) {
    switch (label) {
      case 'Eğitim':
        return const Color(0xFFBFDBFE);
      case 'Toplantı':
        return const Color(0xFFE9D5FF);
      case 'Röportaj':
        return const Color(0xFFFDE68A);
      default:
        return const Color(0xFFF1F5F9);
    }
  }

  void _openFilterSheet(
    BuildContext context,
    Map<String, dynamic> cat,
  ) {
    final String label = cat['label'] as String;
    final Color accent = cat['color'] as Color;
    final Color chipBg = cat['bg'] as Color;
    final IconData icon = cat['icon'] as IconData;

    final List<_RecordItem> filtered =
        recentItems.where((_RecordItem r) => r.category == label).toList();

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (BuildContext ctx) {
        final double maxH = MediaQuery.of(ctx).size.height * 0.70;
        return Container(
          constraints: BoxConstraints(maxHeight: maxH),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.only(top: 14),
                  child: Center(child: _sheetHandle()),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
                  child: Row(
                    children: <Widget>[
                      Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: chipBg,
                          borderRadius: BorderRadius.circular(17),
                        ),
                        child: Icon(icon, color: accent, size: 17),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        '$label Kayıtları',
                        style: GoogleFonts.inter(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                          color: const Color(0xFF1E293B),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: chipBg,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '${filtered.length}',
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: accent,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (filtered.isEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Container(
                            width: 60,
                            height: 60,
                            decoration: BoxDecoration(
                              color: chipBg,
                              borderRadius: BorderRadius.circular(30),
                            ),
                            child: Icon(icon, size: 30, color: accent),
                          ),
                          const SizedBox(height: 14),
                          Text(
                            'Bu kategoride henüz\nkayıt bulunmuyor.',
                            textAlign: TextAlign.center,
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              color: const Color(0xFF94A3B8),
                              fontStyle: FontStyle.italic,
                              height: 1.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  Flexible(
                    child: ListView.separated(
                      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                      itemCount: filtered.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (BuildContext _, int i) {
                        final _RecordItem item = filtered[i];
                        return _DynamicRecordCard(
                          item: item,
                          onTap: () {
                            Navigator.pop(ctx);
                            onRecordTap(item.fileName, item.transcript);
                          },
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    // 'Diğer' hariç ilk 3 kategoriyi göster (orijinal tasarım)
    final List<Map<String, dynamic>> visible = _Cat.all
        .where((Map<String, dynamic> c) => c['label'] != 'Diğer')
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          'Kategoriler',
          style: GoogleFonts.inter(
            fontSize: 14,
            fontWeight: FontWeight.w800,
            color: const Color(0xFF1E293B),
          ),
        ),
        const SizedBox(height: 10),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: visible.map((Map<String, dynamic> cat) {
              final String label = cat['label'] as String;
              final int count = recentItems
                  .where((_RecordItem r) => r.category == label)
                  .length;
              return Padding(
                padding: const EdgeInsets.only(right: 10),
                child: _CategoryCard(
                  bgColor: _solidBg(label),
                  iconColor: _lightIcon(label),
                  title: label,
                  count: count,
                  icon: cat['icon'] as IconData,
                  onTap: () => _openFilterSheet(context, cat),
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }
}

class _CategoryCard extends StatelessWidget {
  const _CategoryCard({
    required this.bgColor,
    required this.iconColor,
    required this.title,
    required this.count,
    required this.icon,
    required this.onTap,
  });

  final Color bgColor;
  final Color iconColor;
  final String title;
  final int count;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        width: 122,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(icon, color: iconColor, size: 20),
            const SizedBox(height: 8),
            Text(
              title,
              style: GoogleFonts.inter(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 13,
              ),
            ),
            Text(
              '$count Kayıt',
              style: GoogleFonts.inter(
                color: Colors.white.withValues(alpha: 0.85),
                fontWeight: FontWeight.w500,
                fontSize: 10,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Acil Görev ───────────────────────────────────────────────────────────────
class _UrgentTaskCard extends StatelessWidget {
  const _UrgentTaskCard();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: <Widget>[
            Text(
              'Acil Görevler',
              style: GoogleFonts.inter(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: const Color(0xFF1E293B),
              ),
            ),
            Text(
              'Tümü',
              style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: const Color(0xFF2563EB),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFF1F5F9)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Icon(Icons.check_box_outline_blank_rounded,
                  color: Color(0xFF94A3B8), size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'Web programlama final ödevini sisteme yükle.',
                      style: GoogleFonts.inter(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF1E293B),
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: <Widget>[
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFEF2F2),
                            borderRadius: BorderRadius.circular(7),
                          ),
                          child: Text(
                            'Yarın',
                            style: GoogleFonts.inter(
                              color: const Color(0xFFDC2626),
                              fontWeight: FontWeight.w700,
                              fontSize: 10,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Icon(Icons.smart_toy_outlined,
                            size: 12, color: Color(0xFF64748B)),
                        const SizedBox(width: 4),
                        Text(
                          'AI tespit etti',
                          style: GoogleFonts.inter(
                            color: const Color(0xFF64748B),
                            fontWeight: FontWeight.w500,
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ─── Son Kayıtlar bölümü ──────────────────────────────────────────────────────
class _RecentSection extends StatelessWidget {
  const _RecentSection({
    required this.isLoading,
    required this.currentFileName,
    required this.currentCategory,
    required this.recentItems,
    required this.onRecordTap,
  });

  final bool isLoading;
  final String currentFileName;
  final String currentCategory;
  final List<_RecordItem> recentItems;
  final void Function(String fileName, String transcript) onRecordTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          'Son Kayıtlar & Analizler',
          style: GoogleFonts.inter(
            fontSize: 14,
            fontWeight: FontWeight.w800,
            color: const Color(0xFF1E293B),
          ),
        ),
        const SizedBox(height: 10),
        if (isLoading) ...<Widget>[
          _ConvertingCard(
            fileName: currentFileName,
            category: currentCategory,
          ),
          const SizedBox(height: 10),
        ],
        if (recentItems.isEmpty && !isLoading)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: Center(
              child: Text(
                'Henüz bir kayıt bulunmuyor.',
                style: GoogleFonts.inter(
                  fontSize: 13,
                  color: const Color(0xFF94A3B8),
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
          )
        else
          ...recentItems.map((_RecordItem item) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _DynamicRecordCard(
                  item: item,
                  onTap: () => onRecordTap(item.fileName, item.transcript),
                ),
              )),
      ],
    );
  }
}

// ─── Dönüştürme kartı (yükleme) ───────────────────────────────────────────────
class _ConvertingCard extends StatelessWidget {
  const _ConvertingCard({
    required this.fileName,
    required this.category,
  });

  final String fileName;
  final String category;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFF1F5F9)),
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: const Color(0xFFFEF3C7),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Center(
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2.4,
                  color: Color(0xFFD97706),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  fileName.isNotEmpty ? fileName : 'Dosya işleniyor...',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF1E293B),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  category.isNotEmpty
                      ? 'FFMPEG Sese Dönüştürüyor... · $category'
                      : 'FFMPEG Sese Dönüştürüyor...',
                  style: GoogleFonts.inter(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFFD97706),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Dinamik kayıt kartı ──────────────────────────────────────────────────────
class _DynamicRecordCard extends StatelessWidget {
  const _DynamicRecordCard({
    required this.item,
    required this.onTap,
  });

  final _RecordItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Color iconBg = _Cat.bg(item.category);
    final Color iconColor = _Cat.color(item.category);
    final IconData icon = _Cat.icon(item.category);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFF1F5F9)),
        ),
        child: Row(
          children: <Widget>[
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: iconBg,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Icon(icon, color: iconColor, size: 19),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    item.fileName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF1E293B),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: <Widget>[
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                          color: iconBg,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          item.category,
                          style: GoogleFonts.inter(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w700,
                            color: iconColor,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          item.transcript,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(
                            fontSize: 10.5,
                            color: const Color(0xFF64748B),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            const Icon(Icons.chevron_right_rounded,
                color: Color(0xFFCBD5E1), size: 18),
          ],
        ),
      ),
    );
  }
}

// ─── Bottom Nav Bar ───────────────────────────────────────────────────────────
class _BottomNavBar extends StatelessWidget {
  const _BottomNavBar({
    required this.selectedIndex,
    required this.onTap,
  });

  final int selectedIndex;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 84,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 22),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFE2E8F0))),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: <Widget>[
          _NavItem(
            label: 'Ana Sayfa',
            icon: Icons.home_rounded,
            selected: selectedIndex == 0,
            onTap: () => onTap(0),
          ),
          _NavItem(
            label: 'Görevler',
            icon: Icons.checklist_rounded,
            selected: selectedIndex == 1,
            onTap: () => onTap(1),
          ),
          const SizedBox(width: 42),
          _NavItem(
            label: 'Kayıtlar',
            icon: Icons.folder_open_rounded,
            selected: selectedIndex == 2,
            onTap: () => onTap(2),
          ),
          _NavItem(
            label: 'Profil',
            icon: Icons.person_outline_rounded,
            selected: false,
            onTap: () => onTap(3),
          ),
        ],
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Color color =
        selected ? const Color(0xFF2563EB) : const Color(0xFF94A3B8);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: SizedBox(
        width: 62,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Icon(icon, size: 20, color: color),
            const SizedBox(height: 3),
            Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
