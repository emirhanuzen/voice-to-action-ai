import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../state/app_state.dart';
import '../services/api_service.dart';
import 'calendar_screen.dart';
import 'chat_screen.dart';
import 'profile_screen.dart';
import 'record_screen.dart';

// Dosya içi kısaltmalar — AppState'teki public modelleri private takma adlarla
// kullanmaya devam ediyoruz; tüm widget koduna dokunmak zorunda kalmadan.
typedef _RecordItem = RecordItem;
typedef _TaskItem = TaskItem;

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
  // Lokal API servisi yalnızca upload işlemi için burada kaldı;
  // veri listeleri artık AppState üzerinden yönetiliyor.
  final ApiService _apiService = ApiService();

  // Saf UI durumu — hangi alt sekme seçili (AppState'e taşınmadı, sadece bu ekrana ait)
  int _selectedBottomIndex = 0;

  // Takvim → Aksiyonlar çapraz navigasyon
  int? _highlightedTaskId;          // aksiyonlar sekmesinde vurgulanacak görev
  DateTime? _calendarJumpDate;      // takvim sekmesinde açılacak gün

  bool _initialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      _initialized = true;
      // İlk açılışta merkezi durumu yükle
      final AppState appState = context.read<AppState>();
      appState.loadUserIdentity();
      appState.fetchData();
    }
  }

  // Yenile: çekme hareketi (pull-to-refresh) veya kayıt sonrası tetiklenir
  Future<void> _loadInitialData() => context.read<AppState>().fetchData();

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
        final bool isDarkMode = ctx.watch<AppState>().isDarkMode;
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
                  color: isDarkMode ? const Color(0xFFF1F5F9) : const Color(0xFF1E293B),
                ),
              ),
              const SizedBox(height: 16),
              _FabOptionTile(
                icon: Icons.mic_rounded,
                iconBg: const Color(0xFFDBEAFE),
                iconColor: const Color(0xFF2563EB),
                title: '🎤  Ses Kaydet',
                subtitle: 'Mikrofon ile yeni kayıt başlat',
                onTap: () async {
                  Navigator.pop(ctx);
                  final Object? result = await Navigator.pushNamed(
                      context, RecordScreen.routeName);
                  if (result == true) _loadInitialData();
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
        final bool isDarkMode = ctx.watch<AppState>().isDarkMode;
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
                  color: isDarkMode ? const Color(0xFFF1F5F9) : const Color(0xFF1E293B),
                ),
              ),
              Text(
                'Bu kaydı hangi kategoriye eklemek istersin?',
                style: GoogleFonts.inter(
                    fontSize: 13, color: isDarkMode ? const Color(0xFF94A3B8) : const Color(0xFF64748B)),
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
                        color: isDarkMode ? const Color(0xFF334155) : (cat['bg'] as Color),
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
                              color: isDarkMode ? const Color(0xFFF1F5F9) : const Color(0xFF1E293B),
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
    final AppState appState = context.read<AppState>();
    if (appState.isUploadLoading) return;

    final FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.audio,
    );
    if (result == null || result.files.single.path == null) return;

    final String pickedFileName = result.files.single.name.isNotEmpty
        ? result.files.single.name
        : 'Medya Dosyası';

    final String? chosenCategory = await _showCategorySheet();
    if (chosenCategory == null) return;

    appState.setUploadState(
      loading: true,
      fileName: pickedFileName,
      category: chosenCategory,
    );

    print('[HomeScreen] Transkripsiyon başlatıldı: '
        'dosya=$pickedFileName kategori=$chosenCategory');

    Map<String, dynamic>? transcribeResult;
    String? uploadError;
    try {
      transcribeResult = await _apiService.uploadMediaAndTranscribe(
        File(result.files.single.path!),
        category: chosenCategory,
      );
      print('[HomeScreen] Transkripsiyon yanıtı: $transcribeResult');
    } catch (e) {
      print('[HomeScreen] Transkripsiyon istisnası: $e');
      uploadError = e.toString().replaceFirst('Exception: ', '');
      transcribeResult = null;
    } finally {
      // API cevap verse de, hata verse de, timeout yese de loading DURUR.
      appState.setUploadState(loading: false);
    }

    if (!mounted) return;

    // Ağ / timeout / sunucu hatası — Snackbar ile kullanıcıya göster
    if (uploadError != null) {
      _showSnack(uploadError, error: true);
      return;
    }

    // Backend'den uygulama düzeyinde hata mesajı geldi mi?
    final String? backendError =
        transcribeResult?['error'] as String?;
    if (backendError != null && backendError.isNotEmpty) {
      _showSnack(backendError, error: true);
      return;
    }

    final String? text = transcribeResult?['text'] as String?;
    final List<dynamic> newTasksRaw =
        (transcribeResult?['tasks'] as List<dynamic>?) ?? <dynamic>[];

    print('[HomeScreen] Metin: ${text?.length ?? 0} karakter, '
        'görev: ${newTasksRaw.length}');

    if (text != null) {
      appState.insertRecord(
        _RecordItem(
          fileName: pickedFileName,
          category: chosenCategory,
          transcript: text.trim().isEmpty ? '' : text,
          autoTitle: transcribeResult?['auto_title'] as String?,
          originalFilename: transcribeResult?['original_filename'] as String?,
        ),
      );
      if (text.trim().isNotEmpty) {
        for (final dynamic t in newTasksRaw) {
          if (t is Map<String, dynamic>) {
            appState.insertTask(_TaskItem.fromJson(t));
          }
        }
      }
    }

    if (text != null && text.trim().isNotEmpty) {
      _showTranscriptSheet(fileName: pickedFileName, text: text);
      return;
    }

    _showSnack(
      text == null
          ? 'Ses işleme başarısız. Backend çalışıyor mu?'
          : 'Ses kaydında konuşma tespit edilemedi.',
      error: true,
    );
  }

  void _showSnack(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor:
            error ? const Color(0xFFEF4444) : const Color(0xFF16A34A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 4),
        content: Row(
          children: <Widget>[
            Icon(
              error
                  ? Icons.error_outline_rounded
                  : Icons.check_circle_outline_rounded,
              color: Colors.white,
              size: 18,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Görev sil ─────────────────────────────────────────────────────────────
  Future<void> _deleteTask(int index) async {
    final Map<String, dynamic> result =
        await context.read<AppState>().deleteTask(index);
    if (!mounted) return;

    if (result['success'] != true) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: const Color(0xFFEF4444),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12)),
          content: Row(
            children: <Widget>[
              const Icon(Icons.error_outline_rounded,
                  color: Colors.white, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  (result['message'] as String?) ?? 'Görev silinemedi.',
                  style: GoogleFonts.inter(
                      fontWeight: FontWeight.w600, color: Colors.white),
                ),
              ),
            ],
          ),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: const Color(0xFF16A34A),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12)),
          duration: const Duration(seconds: 2),
          content: Row(
            children: <Widget>[
              const Icon(Icons.check_circle_outline_rounded,
                  color: Colors.white, size: 18),
              const SizedBox(width: 8),
              Text(
                'Görev silindi.',
                style: GoogleFonts.inter(
                    fontWeight: FontWeight.w600, color: Colors.white),
              ),
            ],
          ),
        ),
      );
    }
  }

  // ── Görev tikle / geri al ────────────────────────────────────────────────
  Future<void> _toggleTask(int index) async {
    // Optimistic update AppState içinde yapılır; rollback da orada
    final Map<String, dynamic> result =
        await context.read<AppState>().toggleTask(index);
    if (!mounted) return;

    if (result['success'] != true) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          content: Text(
            (result['message'] as String?) ?? 'Görev güncellenemedi.',
            style: GoogleFonts.inter(fontWeight: FontWeight.w600),
          ),
        ),
      );
    }
  }

  // ── Transkript sheet ──────────────────────────────────────────────────────
  // ── Dosya yükleme sonrası transkript önizlemesi (id'siz, hızlı görünüm) ───
  void _showTranscriptSheet({
    required String fileName,
    required String text,
  }) {
    // Yeni yüklenen dosyanın kaydedilmiş _RecordItem'ını bulmaya çalış
    final List<_RecordItem> recs = context.read<AppState>().records;
    final int idx = recs.indexWhere(
      (r) => r.transcript == text || r.fileName == fileName,
    );

    // Kayıt bulunduysa zengin detay sheet'i aç, bulunamadıysa basit görünüm
    if (idx != -1) {
      _showRecordDetailSheet(recs[idx], idx);
      return;
    }

    // Kayıt henüz listede yoksa (yükleme taze) → sade önizleme
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
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
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
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
                  child: Row(
                    children: <Widget>[
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFFDCFCE7),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            const Icon(Icons.check_circle_outline_rounded,
                                color: Color(0xFF16A34A), size: 13),
                            const SizedBox(width: 4),
                            Text(
                              'Analiz Tamamlandı',
                              style: GoogleFonts.inter(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: const Color(0xFF16A34A),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 6),
                  child: Text(
                    fileName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                      color: const Color(0xFF1E293B),
                    ),
                  ),
                ),
                const Divider(height: 1, color: Color(0xFFF1F5F9)),
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
                    child: Text(
                      text,
                      style: GoogleFonts.inter(
                        fontSize: 14.5,
                        height: 1.75,
                        color: const Color(0xFF1E293B),
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

  // ── Kayıt sil ─────────────────────────────────────────────────────────────
  Future<void> _deleteRecord(_RecordItem item, int index) async {
    final bool ok = await context.read<AppState>().deleteRecord(index);
    if (!mounted) return;

    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: const Color(0xFFEF4444),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          content: Text('Kayıt silinemedi.',
              style: GoogleFonts.inter(
                  fontWeight: FontWeight.w600, color: Colors.white)),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: const Color(0xFF16A34A),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          duration: const Duration(seconds: 2),
          content: Row(
            children: <Widget>[
              const Icon(Icons.check_circle_outline_rounded,
                  color: Colors.white, size: 18),
              const SizedBox(width: 8),
              Text('Kayıt silindi.',
                  style: GoogleFonts.inter(
                      fontWeight: FontWeight.w600, color: Colors.white)),
            ],
          ),
        ),
      );
    }
  }

  // ── Detay sheet (kayıt listesindeki kartlar için) ─────────────────────────
  void _showRecordDetailSheet(_RecordItem item, int index) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (BuildContext ctx) => _RecordDetailSheet(
        item: item,
        onDelete: () {
          Navigator.pop(ctx);
          _deleteRecord(item, index);
        },
        dateLabel: _recordDateLabel(item.createdAt),
      ),
    );
  }

  // ── Kayıt tarihi etiketi ──────────────────────────────────────────────────
  String _recordDateLabel(DateTime? dt) {
    if (dt == null) return '';
    final DateTime now = DateTime.now();
    final DateTime today = DateTime(now.year, now.month, now.day);
    final DateTime dtDay = DateTime(dt.year, dt.month, dt.day);
    final int diff = today.difference(dtDay).inDays;
    if (diff == 0) return 'Bugün · ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    if (diff == 1) return 'Dün · ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    const List<String> months = <String>[
      'Oca', 'Şub', 'Mar', 'Nis', 'May', 'Haz',
      'Tem', 'Ağu', 'Eyl', 'Eki', 'Kas', 'Ara',
    ];
    return '${dt.day} ${months[dt.month - 1]} ${dt.year}';
  }

  // ── Bildirim çanı modalı ──────────────────────────────────────────────────
  void _showBellModal(int pendingCount) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (BuildContext ctx) {
        final bool isDarkMode = ctx.watch<AppState>().isDarkMode;
        return _SheetContainer(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _sheetHandle(),
              const SizedBox(height: 16),
              Row(
                children: <Widget>[
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: pendingCount > 0
                          ? const Color(0xFFFEF2F2)
                          : const Color(0xFFDCFCE7),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Icon(
                      pendingCount > 0
                          ? Icons.notifications_active_rounded
                          : Icons.notifications_none_rounded,
                      color: pendingCount > 0
                          ? const Color(0xFFEF4444)
                          : const Color(0xFF16A34A),
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Bildirimler',
                    style: GoogleFonts.inter(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: isDarkMode ? const Color(0xFFF1F5F9) : const Color(0xFF1E293B),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: pendingCount > 0
                      ? const Color(0xFFFFF7ED)
                      : const Color(0xFFDCFCE7),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: pendingCount > 0
                        ? const Color(0xFFFED7AA)
                        : const Color(0xFFBBF7D0),
                  ),
                ),
                child: Row(
                  children: <Widget>[
                    Icon(
                      pendingCount > 0
                          ? Icons.pending_actions_rounded
                          : Icons.check_circle_outline_rounded,
                      color: pendingCount > 0
                          ? const Color(0xFFEA580C)
                          : const Color(0xFF16A34A),
                      size: 22,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        pendingCount > 0
                            ? 'Bekleyen $pendingCount adet göreviniz var.'
                            : 'Tüm görevler tamamlandı, harikasın! 🎉',
                        style: GoogleFonts.inter(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                          color: pendingCount > 0
                              ? const Color(0xFFEA580C)
                              : const Color(0xFF16A34A),
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (pendingCount > 0) ...<Widget>[
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2563EB),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                      elevation: 0,
                    ),
                    icon: const Icon(Icons.checklist_rounded, size: 18),
                    label: Text(
                      'Görevlere Git',
                      style: GoogleFonts.inter(
                          fontWeight: FontWeight.w700, fontSize: 14),
                    ),
                    onPressed: () {
                      Navigator.pop(ctx);
                      setState(() => _selectedBottomIndex = 1);
                    },
                  ),
                ),
              ],
              const SizedBox(height: 4),
            ],
          ),
        );
      },
    );
  }

  // ── Nav ───────────────────────────────────────────────────────────────────
  void _onBottomNavTap(int index) {
    if (index == 4) {
      Navigator.pushNamed(context, ProfileScreen.routeName);
      return;
    }
    setState(() {
      _selectedBottomIndex = index;
      // Sekme değişince highlight/jump temizle
      if (index != 1) _highlightedTaskId = null;
      if (index != 2) _calendarJumpDate = null;
    });
  }

  /// Aksiyon kart tarihine tıklanınca → Takvim sekmesine git, o günü seç.
  void _goToCalendarDay(DateTime date) {
    setState(() {
      _calendarJumpDate = date;
      _selectedBottomIndex = 2;
    });
  }

  /// Takvim görev kartına tıklanınca → Aksiyonlar sekmesine git, görevi vurgula.
  void _goToTaskHighlight(int taskId) {
    setState(() {
      _highlightedTaskId = taskId;
      _selectedBottomIndex = 1;
    });
    // 2 saniye sonra vurguyu kaldır
    Future<void>.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _highlightedTaskId = null);
    });
  }

  /// Takvim görev kartından → Kayıtlar sekmesine git + kaydı detay sheet ile aç.
  void _openRecordById(int recordId) {
    final AppState appState = context.read<AppState>();
    final int idx =
        appState.records.indexWhere((_RecordItem r) => r.id == recordId);
    if (idx == -1) return;
    final _RecordItem item = appState.records[idx];
    setState(() => _selectedBottomIndex = 3);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _showRecordDetailSheet(item, idx);
    });
  }

  // ── Build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    // Merkezi durum yönetimi — AppState değiştiğinde bu build otomatik çalışır.
    final AppState appState = context.watch<AppState>();

    final String displayName = appState.userName;
    final int pendingCount =
        appState.tasks.where((_TaskItem t) => t.status != 'done').length;

    Widget body;
    switch (_selectedBottomIndex) {
      case 1:
        body = _TasksPage(
          tasks: appState.tasks,
          isLoading: appState.isInitialLoading,
          onToggle: _toggleTask,
          onDelete: _deleteTask,
          onRefresh: _loadInitialData,
          highlightedTaskId: _highlightedTaskId,
          onDateTap: _goToCalendarDay,
        );
      case 2:
        body = CalendarScreen(
          initialDate: _calendarJumpDate,
          onNavigateToTask: _goToTaskHighlight,
          onOpenRecord: _openRecordById,
        );
      case 3:
        body = _RecordsPage(
          recentItems: appState.records,
          onRecordTap: (_RecordItem item, int idx) =>
              _showRecordDetailSheet(item, idx),
          onRefresh: _loadInitialData,
        );
      default:
        body = _HomePage(
          displayName: displayName,
          initials: _buildInitials(displayName),
          onProfileTap: () =>
              Navigator.pushNamed(context, ProfileScreen.routeName),
          isLoading: appState.isUploadLoading,
          isInitialLoading: appState.isInitialLoading,
          currentFileName: appState.currentFileName,
          currentCategory: appState.currentCategory,
          recentItems: appState.records,
          tasks: appState.tasks,
          pendingCount: pendingCount,
          onBellTap: () => _showBellModal(pendingCount),
          onUploadTap: _showFabOptions,
          onViewAllTasks: () => setState(() => _selectedBottomIndex = 1),
          onRecordTap: (_RecordItem item, int idx) =>
              _showRecordDetailSheet(item, idx),
          onRefresh: _loadInitialData,
        );
    }

    final bool isDarkMode = appState.isDarkMode;

    return Scaffold(
      backgroundColor: isDarkMode ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
      bottomNavigationBar: _BottomNavBar(
        selectedIndex: _selectedBottomIndex,
        onTap: _onBottomNavTap,
      ),
      body: Stack(
        children: <Widget>[
          SafeArea(child: body),
          // ── Chatbot FAB ───────────────────────────────
          Positioned(
            right: 16,
            bottom: 16,
            child: _ChatFab(
              onTap: () => Navigator.pushNamed(context, ChatScreen.routeName),
            ),
          ),
          // ── Mikrofon FAB — merkez alt ─────────────────
          Positioned(
            bottom: 18,
            left: 0,
            right: 0,
            child: Center(
              child: GestureDetector(
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
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Chatbot Floating Action Button ──────────────────────────────────────────
class _ChatFab extends StatefulWidget {
  const _ChatFab({required this.onTap});

  final VoidCallback onTap;

  @override
  State<_ChatFab> createState() => _ChatFabState();
}

class _ChatFabState extends State<_ChatFab>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat(reverse: true);
    _scale = Tween<double>(begin: 0.95, end: 1.05).animate(
      CurvedAnimation(parent: _pulse, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _scale,
      child: GestureDetector(
        onTap: widget.onTap,
        child: Stack(
          alignment: Alignment.center,
          children: <Widget>[
            // Dış parlama halkası
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: <Color>[
                    const Color(0xFFEF4444).withValues(alpha: 0.28),
                    const Color(0xFFEA580C).withValues(alpha: 0.0),
                  ],
                ),
              ),
            ),
            // Ana buton
            Container(
              width: 64,
              height: 64,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: Color(0x446366F1),
                    blurRadius: 12,
                    offset: Offset(0, 4),
                  ),
                ],
              ),
              child: ClipOval(
                child: Image.asset(
                  'assets/voice_assistant.png',
                  width: 64,
                  height: 64,
                  fit: BoxFit.cover,
                ),
              ),
            ),
          ],
        ),
      ),
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
    required this.isInitialLoading,
    required this.currentFileName,
    required this.currentCategory,
    required this.recentItems,
    required this.tasks,
    required this.pendingCount,
    required this.onBellTap,
    required this.onUploadTap,
    required this.onViewAllTasks,
    required this.onRecordTap,
    this.onRefresh,
  });

  final String displayName;
  final String initials;
  final VoidCallback onProfileTap;
  final bool isLoading;
  final bool isInitialLoading;
  final String currentFileName;
  final String currentCategory;
  final List<_RecordItem> recentItems;
  final List<_TaskItem> tasks;
  final int pendingCount;
  final VoidCallback onBellTap;
  final VoidCallback onUploadTap;
  final VoidCallback onViewAllTasks;
  final void Function(_RecordItem item, int index) onRecordTap;
  final Future<void> Function()? onRefresh;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        _Header(
          displayName: displayName,
          initials: initials,
          onProfileTap: onProfileTap,
          pendingCount: pendingCount,
          onBellTap: onBellTap,
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: onRefresh ?? () async {},
            color: const Color(0xFF2563EB),
            child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 110),
            children: <Widget>[
              // ── Özet istatistik satırı ───────────────────────────────────
              _StatsRow(
                totalRecords: recentItems.length,
                pendingCount: pendingCount,
                isLoading: isInitialLoading,
              ),
              const SizedBox(height: 18),
              _QuickActionCard(onTap: onUploadTap),
              const SizedBox(height: 16),
              // ── 🔥 Alevli Kritik Hatırlatma Paneli ─────────────────────────
              // Sadece bugün/yarın/bu hafta içi görev varsa görünür;
              // yoksa SizedBox.shrink() döner (tamamen gizlenir).
              _UrgentTaskCard(
                tasks: tasks,
                isLoading: isInitialLoading,
                onViewAll: onViewAllTasks,
              ),
              const SizedBox(height: 16),
              _CategorySection(
                recentItems: recentItems,
                onRecordTap: onRecordTap,
              ),
              const SizedBox(height: 22),
              _RecentSection(
                isLoading: isLoading,
                isInitialLoading: isInitialLoading,
                currentFileName: currentFileName,
                currentCategory: currentCategory,
                recentItems: recentItems,
                onRecordTap: onRecordTap,
              ),
            ],
            ),  // ListView
          ),    // RefreshIndicator
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// SAYFA: Görevler
// ═══════════════════════════════════════════════════════════════════════════════
class _TasksPage extends StatelessWidget {
  const _TasksPage({
    required this.tasks,
    this.isLoading = false,
    this.onToggle,
    this.onDelete,
    this.onRefresh,
    this.highlightedTaskId,
    this.onDateTap,
  });

  final List<_TaskItem> tasks;
  final bool isLoading;
  final void Function(int index)? onToggle;
  final void Function(int index)? onDelete;
  final Future<void> Function()? onRefresh;
  final int? highlightedTaskId;
  final void Function(DateTime date)? onDateTap;

  @override
  Widget build(BuildContext context) {
    final bool isDarkMode = context.watch<AppState>().isDarkMode;

    if (isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFF4F46E5)),
      );
    }

    if (tasks.isEmpty) {
      return Container(
        color: isDarkMode ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: isDarkMode ? const Color(0xFF334155) : const Color(0xFFEEF2FF),
                borderRadius: BorderRadius.circular(36),
              ),
              child: const Icon(Icons.checklist_rounded,
                  size: 36, color: Color(0xFF4F46E5)),
            ),
            const SizedBox(height: 16),
            Text(
              'Bekleyen Aksiyon Bulunmuyor',
              style: GoogleFonts.inter(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: isDarkMode ? const Color(0xFFF1F5F9) : const Color(0xFF1E293B),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Ses kayıtlarından AI otomatik\naksiyon çıkardığında burada görünecek.',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: 13,
                color: isDarkMode ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                height: 1.5,
              ),
            ),
          ],
          ),      // Column
        ),        // Center
      );          // Container
    }

    return Container(
      color: isDarkMode ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
      child: RefreshIndicator(
        onRefresh: onRefresh ?? () async {},
        color: const Color(0xFF2563EB),
        child: ListView.separated(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 110),
      itemCount: tasks.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (BuildContext context, int i) {
        final _TaskItem task = tasks[i];
        return Dismissible(
          key: ValueKey<Object>(task.id ?? 'task_$i'),
          direction: DismissDirection.endToStart,
          behavior: HitTestBehavior.opaque,
          // Kaydırma sırasında arkada görünen kırmızı arka plan
          background: Container(
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 24),
            decoration: BoxDecoration(
              color: const Color(0xFFEF4444),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const Icon(
                  Icons.delete_sweep_rounded,
                  color: Colors.white,
                  size: 26,
                ),
                const SizedBox(height: 4),
                Text(
                  'Sil',
                  style: GoogleFonts.inter(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          confirmDismiss: (_) async {
            // Tamamlanmış görevler için hızlı onay iste
            if (task.status == 'done') {
              return await showDialog<bool>(
                    context: context,
                    builder: (BuildContext ctx) => AlertDialog(
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20)),
                      title: Text(
                        'Görevi Sil',
                        style: GoogleFonts.inter(
                            fontWeight: FontWeight.w800,
                            color: const Color(0xFF1E293B)),
                      ),
                      content: Text(
                        'Bu görev zaten tamamlandı. Yine de silmek istiyor musun?',
                        style: GoogleFonts.inter(
                            color: const Color(0xFF64748B), height: 1.5),
                      ),
                      actions: <Widget>[
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: Text('İptal',
                              style: GoogleFonts.inter(
                                  color: const Color(0xFF64748B))),
                        ),
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          child: Text(
                            'Sil',
                            style: GoogleFonts.inter(
                              color: const Color(0xFFEF4444),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ) ??
                  false;
            }
            return true;
          },
          onDismissed: (_) {
            if (onDelete != null) onDelete!(i);
          },
          child: Theme(
            data: Theme.of(context).copyWith(
              splashColor: Colors.transparent,
              highlightColor: Colors.transparent,
              splashFactory: NoSplash.splashFactory,
            ),
            child: _TaskCard(
              task: task,
              isDarkMode: isDarkMode,
              onToggle: onToggle != null ? () => onToggle!(i) : null,
              onDelete: onDelete != null ? () => onDelete!(i) : null,
              isHighlighted: task.id != null && task.id == highlightedTaskId,
              onDateTap: onDateTap,
            ),
          ),
        );
      },
      ),   // ListView.separated
      ),   // RefreshIndicator
    );     // Container
  }
}

// ─── Görev kartı ──────────────────────────────────────────────────────────────
class _TaskCard extends StatelessWidget {
  const _TaskCard({
    required this.task,
    required this.isDarkMode,
    this.onToggle,
    this.onDelete,
    this.isHighlighted = false,
    this.onDateTap,
  });

  final _TaskItem task;
  final bool isDarkMode;
  final VoidCallback? onToggle;
  final VoidCallback? onDelete;
  /// Takvimden gelinince kısa süre parlayan vurgulama.
  final bool isHighlighted;
  /// Tarih rozetine tıklanınca — takvim sekmesine git.
  final void Function(DateTime date)? onDateTap;

  @override
  Widget build(BuildContext context) {
    final DateTime? dt = _parseDate(task.dueDate);
    final bool isDone = task.status == 'done';

    // Tarih rozet bilgisi
    String? dateLabel;
    Color dateBg = const Color(0xFFF1F5F9);
    Color dateText = const Color(0xFF64748B);
    if (dt != null && !isDone) {
      final (:Color bg, :Color text) = _urgencyColors(dt);
      dateLabel = _smartDateLabel(dt);
      dateBg   = bg;
      dateText = text;
    } else if (dt != null && isDone) {
      dateLabel = _smartDateLabel(dt);
    }

    final Color cardBg = isDone
        ? (isDarkMode ? const Color(0xFF1A2535) : const Color(0xFFF8FAFC))
        : (isDarkMode ? const Color(0xFF1E293B) : Colors.white);
    final Color cardBorder = isDarkMode
        ? const Color(0xFF334155)
        : (isDone ? const Color(0xFFE2E8F0) : const Color(0xFFF1F5F9));

    return Theme(
      data: Theme.of(context).copyWith(
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
        splashFactory: NoSplash.splashFactory,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
        onTap: onToggle,
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
        hoverColor: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isHighlighted
              ? const Color(0xFFF59E0B)
              : cardBorder,
          width: isHighlighted ? 2 : 1,
        ),
        boxShadow: isHighlighted
            ? const <BoxShadow>[
                BoxShadow(
                  color: Color(0x33F59E0B),
                  blurRadius: 12,
                  offset: Offset(0, 3),
                ),
              ]
            : (isDone
                ? const <BoxShadow>[]
                : <BoxShadow>[
                    BoxShadow(
                      color: isDarkMode
                          ? Colors.transparent
                          : const Color(0x0A0F172A),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ]),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // ── Tıklanabilir checkbox ────────────────────────────────────────
          GestureDetector(
            onTap: onToggle,
            behavior: HitTestBehavior.opaque,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: isDone
                    ? (isDarkMode ? const Color(0xFF14532D) : const Color(0xFFDCFCE7))
                    : (isDarkMode ? const Color(0xFF1E3A5F) : const Color(0xFFEDE9FE)),
                borderRadius: BorderRadius.circular(20),
              ),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: Icon(
                  isDone ? Icons.check_rounded : Icons.circle_outlined,
                  key: ValueKey<bool>(isDone),
                  color: isDone
                      ? (isDarkMode ? const Color(0xFF4ADE80) : const Color(0xFF16A34A))
                      : (isDarkMode ? const Color(0xFF3B82F6) : const Color(0xFF6366F1)),
                  size: 20,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          // ── Görev metni ve tarih ─────────────────────────────────────────
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                AnimatedDefaultTextStyle(
                  duration: const Duration(milliseconds: 200),
                  style: GoogleFonts.inter(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: isDone
                        ? (isDarkMode ? const Color(0xFF475569) : const Color(0xFFCBD5E1))
                        : (isDarkMode ? const Color(0xFFF1F5F9) : const Color(0xFF1E293B)),
                    height: 1.35,
                    decoration: isDone
                        ? TextDecoration.lineThrough
                        : TextDecoration.none,
                    decorationColor: const Color(0xFFCBD5E1),
                    decorationThickness: 1.5,
                  ),
                  child: Text(task.title),
                ),
                const SizedBox(height: 6),
                Row(
                  children: <Widget>[
                    // ── Tarih rozeti (tıklanabilir → takvim) ──────────────
                    if (dateLabel != null)
                      GestureDetector(
                        onTap: (dt != null && onDateTap != null && !isDone)
                            ? () => onDateTap!(dt)
                            : null,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: isDone
                                ? const Color(0xFFF1F5F9)
                                : (isDarkMode
                                    ? dateText.withValues(alpha: 0.25)
                                    : dateBg),
                            borderRadius: BorderRadius.circular(7),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              Icon(
                                Icons.calendar_today_rounded,
                                size: 9,
                                color: isDone
                                    ? const Color(0xFFCBD5E1)
                                    : dateText,
                              ),
                              const SizedBox(width: 3),
                              Text(
                                dateLabel,
                                style: GoogleFonts.inter(
                                  color: isDone
                                      ? const Color(0xFFCBD5E1)
                                      : dateText,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 10,
                                ),
                              ),
                              if (onDateTap != null && !isDone) ...<Widget>[
                                const SizedBox(width: 3),
                                Icon(
                                  Icons.open_in_new_rounded,
                                  size: 8,
                                  color: isDone
                                      ? const Color(0xFFCBD5E1)
                                      : dateText,
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    if (dateLabel != null) const SizedBox(width: 6),
                    Icon(
                      Icons.support_agent_rounded,
                      size: 11,
                      color: isDone
                          ? const Color(0xFFCBD5E1)
                          : const Color(0xFF64748B),
                    ),
                    const SizedBox(width: 3),
                    Text(
                      'AI tespit etti',
                      style: GoogleFonts.inter(
                        color: isDone
                            ? const Color(0xFFCBD5E1)
                            : const Color(0xFF64748B),
                        fontSize: 10,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // ── Çöp kutusu ──────────────────────────────────────────────────
          if (onDelete != null) ...<Widget>[
            const SizedBox(width: 8),
            GestureDetector(
              onTap: onDelete,
              behavior: HitTestBehavior.opaque,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: isDone
                      ? (isDarkMode ? const Color(0xFF334155) : const Color(0xFFF1F5F9))
                      : (isDarkMode ? const Color(0xFF2D1B1B) : const Color(0xFFFFF1F2)),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.delete_outline_rounded,
                  size: 15,
                  color: isDone
                      ? const Color(0xFFCBD5E1)
                      : const Color(0xFFE11D48),
                ),
              ),
            ),
          ],
        ],
      ),
        ),   // AnimatedContainer
      ),     // InkWell
      ),     // Material
    );       // Theme
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// SAYFA: Kayıtlar
// ═══════════════════════════════════════════════════════════════════════════════
class _RecordsPage extends StatelessWidget {
  const _RecordsPage({
    required this.recentItems,
    required this.onRecordTap,
    this.onRefresh,
  });

  final List<_RecordItem> recentItems;
  final void Function(_RecordItem item, int index) onRecordTap;
  final Future<void> Function()? onRefresh;

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

    return RefreshIndicator(
      onRefresh: onRefresh ?? () async {},
      color: const Color(0xFF2563EB),
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 110),
        itemCount: recentItems.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (BuildContext context, int i) {
          final _RecordItem item = recentItems[i];
          return _DynamicRecordCard(
            item: item,
            onTap: () => onRecordTap(item, i),
          );
        },
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// YARDIMCI: Tarih formatlama + aciliyet renkleri
// ═══════════════════════════════════════════════════════════════════════════════

/// ISO tarih stringini ("2026-05-02") parse eder.
/// Null veya boşsa null döner.
DateTime? _parseDate(String? iso) {
  if (iso == null || iso.isEmpty) return null;
  try {
    return DateTime.parse(iso);
  } catch (_) {
    return null;
  }
}

/// Tarihi insan dostu kısa metne çevirir:
///   geçmiş  → "Gecikti"
///   bugün   → "Bugün"
///   yarın   → "Yarın"
///   2 gün   → "Öbür gün"
///   3-6 gün → "Perşembe" (gün adı)
///   7+ gün  → "12 May"
String _smartDateLabel(DateTime dt) {
  const List<String> _tr_months = <String>[
    'Oca', 'Şub', 'Mar', 'Nis', 'May', 'Haz',
    'Tem', 'Ağu', 'Eyl', 'Eki', 'Kas', 'Ara',
  ];
  const List<String> _tr_days = <String>[
    'Pazartesi', 'Salı', 'Çarşamba', 'Perşembe', 'Cuma', 'Cumartesi', 'Pazar',
  ];

  final DateTime now = DateTime.now();
  final DateTime today = DateTime(now.year, now.month, now.day);
  final DateTime dtDay = DateTime(dt.year, dt.month, dt.day);
  final int diff = dtDay.difference(today).inDays;

  if (diff < 0)  return 'Gecikti';
  if (diff == 0) return 'Bugün';
  if (diff == 1) return 'Yarın';
  if (diff == 2) return 'Öbür gün';
  if (diff <= 6) return _tr_days[dt.weekday - 1];
  return '${dt.day} ${_tr_months[dt.month - 1]}';
}

/// Aciliyet seviyesine göre rozet renkleri döner.
///   0 → kırmızı (geçmiş)
///   1 → turuncu (≤ 48 saat)
///   2 → indigo  (≤ 7 gün)
///   3 → gri     (uzak)
({Color bg, Color text}) _urgencyColors(DateTime dt) {
  final DateTime now = DateTime.now();
  final DateTime today = DateTime(now.year, now.month, now.day);
  final int diff = DateTime(dt.year, dt.month, dt.day).difference(today).inDays;

  if (diff < 0)  return (bg: const Color(0xFFFEE2E2), text: const Color(0xFFEF4444));
  if (diff <= 1) return (bg: const Color(0xFFFFEDD5), text: const Color(0xFFF97316));
  if (diff <= 6) return (bg: const Color(0xFFDBEAFE), text: const Color(0xFF2563EB));
  return           (bg: const Color(0xFFF1F5F9), text: const Color(0xFF94A3B8));
}

// ═══════════════════════════════════════════════════════════════════════════════
// KAYIT DETAY SHEET — Arama + Highlight + Scroll-to-Match
// ═══════════════════════════════════════════════════════════════════════════════
class _RecordDetailSheet extends StatefulWidget {
  const _RecordDetailSheet({
    required this.item,
    required this.onDelete,
    required this.dateLabel,
  });

  final _RecordItem item;
  final VoidCallback onDelete;
  final String dateLabel;

  @override
  State<_RecordDetailSheet> createState() => _RecordDetailSheetState();
}

class _RecordDetailSheetState extends State<_RecordDetailSheet>
    with TickerProviderStateMixin {
  final TextEditingController _searchCtrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();
  final GlobalKey _textKey = GlobalKey();
  late final TabController _tabCtrl;

  String _query = '';
  int _matchCount = 0;
  int _currentMatch = 0; // 0-indexed

  AudioPlayer? _player;
  bool _isPlaying = false;
  bool _isLoadingAudio = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;

  late final TextEditingController _noteCtrl;
  bool _isSavingNote = false;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
    _noteCtrl = TextEditingController(text: widget.item.notes ?? '');
  }

  @override
  void dispose() {
    _player?.dispose();
    _tabCtrl.dispose();
    _noteCtrl.dispose();
    _searchCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  /// İlk kez çalarken dosyayı indirir, sonrasında pause/resume yapar.
  Future<void> _togglePlay() async {
    final int? id = widget.item.id;
    if (id == null) return;

    // Zaten yüklü oynatıcı varsa → pause / resume
    if (_player != null && _duration > Duration.zero) {
      if (_isPlaying) {
        await _player!.pause();
        if (mounted) setState(() => _isPlaying = false);
      } else {
        await _player!.resume();
        if (mounted) setState(() => _isPlaying = true);
      }
      return;
    }

    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? token = prefs.getString('access_token');
    if (token == null || token.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Oturum bulunamadı, lütfen tekrar giriş yapın.')),
        );
      }
      return;
    }

    if (mounted) setState(() => _isLoadingAudio = true);

    try {
      // ── 1. Ses dosyasını cache'e indir ─────────────────────────────────
      final String url =
          '${ApiService().audioUrl(id)}?token=${Uri.encodeComponent(token)}';
      final http.Response response = await http.get(Uri.parse(url));

      if (response.statusCode != 200) {
        throw Exception('Sunucu hatası: ${response.statusCode}');
      }

      final Directory cacheDir = await getTemporaryDirectory();
      final String ext =
          _extFromContentType(response.headers['content-type'] ?? '') ?? '.mp4';
      final File tmpFile = File('${cacheDir.path}/audio_$id$ext');
      await tmpFile.writeAsBytes(response.bodyBytes);

      // ── 2. Oynatıcıyı kur ve dinle ──────────────────────────────────────
      _player = AudioPlayer();

      _player!.onDurationChanged.listen((Duration d) {
        if (mounted) setState(() => _duration = d);
      });
      _player!.onPositionChanged.listen((Duration p) {
        if (mounted) setState(() => _position = p);
      });
      _player!.onPlayerComplete.listen((_) {
        if (mounted) {
          setState(() {
            _isPlaying = false;
            _position = Duration.zero;
          });
        }
      });

      await _player!.play(DeviceFileSource(tmpFile.path));
      if (mounted) setState(() => _isPlaying = true);
    } catch (e) {
      debugPrint('[AudioPlayer] HATA: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ses çalınamadı: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoadingAudio = false);
    }
  }

  Future<void> _seek(Duration delta) async {
    if (_player == null) return;
    final Duration raw = _position + delta;
    final Duration target = raw < Duration.zero
        ? Duration.zero
        : (raw > _duration ? _duration : raw);
    await _player!.seek(target);
  }

  String _fmtDuration(Duration d) {
    final int m = d.inMinutes;
    final int s = d.inSeconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  /// Content-Type başlığından dosya uzantısı döndürür.
  String? _extFromContentType(String ct) {
    if (ct.contains('mp4') || ct.contains('m4a')) return '.mp4';
    if (ct.contains('mpeg') || ct.contains('mp3')) return '.mp3';
    if (ct.contains('webm')) return '.webm';
    if (ct.contains('ogg')) return '.ogg';
    if (ct.contains('wav')) return '.wav';
    if (ct.contains('flac')) return '.flac';
    return null;
  }

  // ─── Sarı highlight için RichText span'ları üret ───────────────────────────
  List<TextSpan> _buildSpans(String text, String query, {bool isDarkMode = false}) {
    if (query.isEmpty) {
      return <TextSpan>[
        TextSpan(
          text: text,
          style: GoogleFonts.inter(
            fontSize: 14.5,
            height: 1.75,
            color: isDarkMode ? const Color(0xFFF1F5F9) : const Color(0xFF1E293B),
          ),
        ),
      ];
    }

    final List<TextSpan> spans = <TextSpan>[];
    final String lowerText = text.toLowerCase();
    final String lowerQuery = query.toLowerCase();
    int start = 0;
    int count = 0;

    while (true) {
      final int idx = lowerText.indexOf(lowerQuery, start);
      if (idx == -1) break;

      // Normal metin — eşleşmeden öncesi
      if (idx > start) {
        spans.add(TextSpan(
          text: text.substring(start, idx),
          style: GoogleFonts.inter(
            fontSize: 14.5,
            height: 1.75,
            color: isDarkMode ? const Color(0xFFF1F5F9) : const Color(0xFF1E293B),
          ),
        ));
      }

      // Vurgulanan eşleşme
      final bool isCurrent = count == _currentMatch;
      spans.add(TextSpan(
        text: text.substring(idx, idx + query.length),
        style: GoogleFonts.inter(
          fontSize: 14.5,
          height: 1.75,
          fontWeight: FontWeight.w700,
          color: isCurrent ? const Color(0xFF92400E) : (isDarkMode ? const Color(0xFFF1F5F9) : const Color(0xFF1E293B)),
          backgroundColor:
              isCurrent ? const Color(0xFFFDE68A) : const Color(0xFFFEF9C3),
        ),
      ));

      start = idx + query.length;
      count++;
    }

    // Kalan metin
    if (start < text.length) {
      spans.add(TextSpan(
        text: text.substring(start),
        style: GoogleFonts.inter(
          fontSize: 14.5,
          height: 1.75,
          color: isDarkMode ? const Color(0xFFF1F5F9) : const Color(0xFF1E293B),
        ),
      ));
    }

    return spans;
  }

  // ─── Kaç eşleşme var? ─────────────────────────────────────────────────────
  int _countMatches(String text, String query) {
    if (query.isEmpty) return 0;
    int count = 0;
    int idx = 0;
    final String lower = text.toLowerCase();
    final String lq = query.toLowerCase();
    while (true) {
      idx = lower.indexOf(lq, idx);
      if (idx == -1) break;
      count++;
      idx += lq.length;
    }
    return count;
  }

  // ─── Aktif eşleşmeye scroll et ────────────────────────────────────────────
  void _scrollToCurrentMatch(String text) {
    if (_matchCount == 0 || !_scrollCtrl.hasClients) return;

    // Metin içindeki konumu piksel cinsine çevir
    final String lower = text.toLowerCase();
    final String lq = _query.toLowerCase();

    int matchIdx = 0;
    int charPos = 0;
    while (matchIdx < _currentMatch) {
      final int found = lower.indexOf(lq, charPos);
      if (found == -1) return;
      charPos = found + lq.length;
      matchIdx++;
    }
    final int targetChar = lower.indexOf(lq, charPos);
    if (targetChar == -1) return;

    // Her satır yaklaşık kaç karakter? Ekrana göre estimate
    // RenderBox kullanmak daha doğru ama context gerektirir; burada
    // satır-yüksekliği tahminiyle yeterince doğru bir scroll sağlanır.
    final double lineH = 14.5 * 1.75; // fontSize * lineHeight
    const double charsPerLine = 45.0; // tahmini
    final double approxOffset =
        (targetChar / charsPerLine) * lineH;
    _scrollCtrl.animateTo(
      approxOffset.clamp(0.0, _scrollCtrl.position.maxScrollExtent),
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOut,
    );
  }

  void _onSearchChanged(String q, String text) {
    setState(() {
      _query = q.trim();
      _matchCount = _countMatches(text, _query);
      _currentMatch = 0;
    });
    WidgetsBinding.instance.addPostFrameCallback(
        (_) => _scrollToCurrentMatch(text));
  }

  void _nextMatch(String text) {
    if (_matchCount == 0) return;
    setState(() => _currentMatch = (_currentMatch + 1) % _matchCount);
    WidgetsBinding.instance.addPostFrameCallback(
        (_) => _scrollToCurrentMatch(text));
  }

  void _prevMatch(String text) {
    if (_matchCount == 0) return;
    setState(() =>
        _currentMatch = (_currentMatch - 1 + _matchCount) % _matchCount);
    WidgetsBinding.instance.addPostFrameCallback(
        (_) => _scrollToCurrentMatch(text));
  }

  @override
  Widget build(BuildContext context) {
    final bool isDarkMode = context.watch<AppState>().isDarkMode;
    final double maxH = MediaQuery.of(context).size.height * 0.88;
    final Color catColor = _Cat.color(widget.item.category);
    final Color catBg = _Cat.bg(widget.item.category);
    final IconData catIcon = _Cat.icon(widget.item.category);
    final String? transcript = widget.item.transcript;
    final String text =
        (transcript != null && transcript.trim().isNotEmpty) ? transcript : '';

    return Container(
      constraints: BoxConstraints(maxHeight: maxH),
      decoration: BoxDecoration(
        color: isDarkMode ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            // ── Drag handle ────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.only(top: 14),
              child: Center(child: _sheetHandle()),
            ),

            // ── Ses oynatıcı ───────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFFEFF6FF),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFBFDBFE)),
                ),
                child: Column(
                  children: <Widget>[
                    // ── Kontrol butonları ──────────────────────────────────
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: <Widget>[
                        // -10 saniye
                        IconButton(
                          onPressed: (_isLoadingAudio || _duration == Duration.zero)
                              ? null
                              : () => _seek(const Duration(seconds: -10)),
                          icon: const Icon(Icons.replay_10_rounded),
                          color: const Color(0xFF2563EB),
                          iconSize: 28,
                          tooltip: '10s geri',
                        ),

                        // Play / Pause / Loading
                        GestureDetector(
                          onTap: _isLoadingAudio ? null : _togglePlay,
                          child: Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              color: _isPlaying
                                  ? const Color(0xFFEF4444)
                                  : const Color(0xFF2563EB),
                              shape: BoxShape.circle,
                            ),
                            child: _isLoadingAudio
                                ? const Padding(
                                    padding: EdgeInsets.all(12),
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.5,
                                      color: Colors.white,
                                    ),
                                  )
                                : Icon(
                                    _isPlaying
                                        ? Icons.pause_rounded
                                        : Icons.play_arrow_rounded,
                                    color: Colors.white,
                                    size: 26,
                                  ),
                          ),
                        ),

                        // +10 saniye
                        IconButton(
                          onPressed: (_isLoadingAudio || _duration == Duration.zero)
                              ? null
                              : () => _seek(const Duration(seconds: 10)),
                          icon: const Icon(Icons.forward_10_rounded),
                          color: const Color(0xFF2563EB),
                          iconSize: 28,
                          tooltip: '10s ileri',
                        ),
                      ],
                    ),

                    // ── İlerleme çubuğu ────────────────────────────────────
                    if (_duration > Duration.zero) ...<Widget>[
                      SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          trackHeight: 3,
                          thumbShape: const RoundSliderThumbShape(
                              enabledThumbRadius: 6),
                          overlayShape: const RoundSliderOverlayShape(
                              overlayRadius: 14),
                          activeTrackColor: const Color(0xFF2563EB),
                          inactiveTrackColor: const Color(0xFFBFDBFE),
                          thumbColor: const Color(0xFF2563EB),
                          overlayColor: Color(0x292563EB),
                        ),
                        child: Slider(
                          value: _position.inMilliseconds
                              .clamp(0, _duration.inMilliseconds)
                              .toDouble(),
                          max: _duration.inMilliseconds.toDouble(),
                          onChanged: (double v) {
                            _player?.seek(
                                Duration(milliseconds: v.toInt()));
                          },
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: <Widget>[
                            Text(
                              _fmtDuration(_position),
                              style: GoogleFonts.inter(
                                  fontSize: 11,
                                  color: isDarkMode ? const Color(0xFF94A3B8) : const Color(0xFF64748B)),
                            ),
                            Text(
                              _fmtDuration(_duration),
                              style: GoogleFonts.inter(
                                  fontSize: 11,
                                  color: isDarkMode ? const Color(0xFF94A3B8) : const Color(0xFF64748B)),
                            ),
                          ],
                        ),
                      ),
                    ] else
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          _isLoadingAudio ? 'İndiriliyor…' : 'Sesi Dinle',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            color: isDarkMode ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),

            // ── Başlık satırı ──────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
              child: Row(
                children: <Widget>[
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: catBg,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(catIcon, color: catColor, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: catBg,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            widget.item.category,
                            style: GoogleFonts.inter(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              color: catColor,
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          widget.item.fileName,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: isDarkMode ? const Color(0xFFF1F5F9) : const Color(0xFF1E293B),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          widget.dateLabel,
                          style: GoogleFonts.inter(
                            fontSize: 11.5,
                            color: isDarkMode ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // ── Arama Çubuğu (sadece transkript varsa) ─────────────────────
            if (text.isNotEmpty) ...<Widget>[
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: Container(
                        height: 40,
                        decoration: BoxDecoration(
                          color: isDarkMode ? const Color(0xFF334155) : const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: _query.isNotEmpty
                                ? const Color(0xFF2563EB)
                                : const Color(0xFFE2E8F0),
                          ),
                        ),
                        child: Row(
                          children: <Widget>[
                            const SizedBox(width: 12),
                            Icon(
                              Icons.search_rounded,
                              size: 16,
                              color: _query.isNotEmpty
                                  ? const Color(0xFF2563EB)
                                  : const Color(0xFF94A3B8),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: TextField(
                                controller: _searchCtrl,
                                onChanged: (v) => _onSearchChanged(v, text),
                                style: GoogleFonts.inter(
                                  fontSize: 13,
                                  color: isDarkMode ? const Color(0xFFF1F5F9) : const Color(0xFF1E293B),
                                ),
                                decoration: InputDecoration(
                                  hintText: 'Transkriptte ara...',
                                  hintStyle: GoogleFonts.inter(
                                    fontSize: 13,
                                    color: isDarkMode ? const Color(0xFF64748B) : const Color(0xFF94A3B8),
                                  ),
                                  border: InputBorder.none,
                                  isDense: true,
                                ),
                              ),
                            ),
                            if (_query.isNotEmpty)
                              GestureDetector(
                                onTap: () {
                                  _searchCtrl.clear();
                                  _onSearchChanged('', text);
                                },
                                child: const Padding(
                                  padding: EdgeInsets.only(right: 8),
                                  child: Icon(Icons.close_rounded,
                                      size: 16, color: Color(0xFF94A3B8)),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    // İleri/Geri navigasyon
                    if (_query.isNotEmpty && _matchCount > 0) ...<Widget>[
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: () => _prevMatch(text),
                        child: Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            color: const Color(0xFFEFF6FF),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.keyboard_arrow_up_rounded,
                              size: 18, color: Color(0xFF2563EB)),
                        ),
                      ),
                      const SizedBox(width: 4),
                      GestureDetector(
                        onTap: () => _nextMatch(text),
                        child: Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            color: const Color(0xFFEFF6FF),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.keyboard_arrow_down_rounded,
                              size: 18, color: Color(0xFF2563EB)),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              // Eşleşme sayısı rozeti
              if (_query.isNotEmpty)
                Padding(
                  padding:
                      const EdgeInsets.only(left: 20, top: 6),
                  child: Text(
                    _matchCount == 0
                        ? 'Sonuç bulunamadı'
                        : '${_currentMatch + 1} / $_matchCount eşleşme',
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: _matchCount == 0
                          ? const Color(0xFFEF4444)
                          : const Color(0xFF2563EB),
                    ),
                  ),
                ),
            ],

            const SizedBox(height: 8),
            Divider(height: 1, thickness: 1, color: isDarkMode ? const Color(0xFF334155) : const Color(0xFFF1F5F9)),

            // ── Sekme başlıkları ───────────────────────────────────────────
            TabBar(
              controller: _tabCtrl,
              labelStyle: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700),
              unselectedLabelStyle: GoogleFonts.inter(fontSize: 12),
              labelColor: const Color(0xFF2563EB),
              unselectedLabelColor: const Color(0xFF64748B),
              indicatorColor: const Color(0xFF2563EB),
              indicatorSize: TabBarIndicatorSize.label,
              tabs: const <Tab>[
                Tab(text: '📄 Transkript'),
                Tab(text: '📝 Notlar'),
              ],
            ),
            // ── Sekme içerikleri ───────────────────────────────────────────
            Flexible(
              child: TabBarView(
                controller: _tabCtrl,
                children: <Widget>[
                  // ── Transkript sekmesi ─────────────────────────────────
                  SingleChildScrollView(
                    controller: _scrollCtrl,
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                    child: () {
                      if (text.isNotEmpty) {
                        return RichText(
                          key: _textKey,
                          text: TextSpan(
                            children: _buildSpans(text, _query, isDarkMode: isDarkMode),
                          ),
                        );
                      }
                      final IconData ic = transcript == null
                          ? Icons.hourglass_top_rounded
                          : Icons.volume_off_rounded;
                      final String label = transcript == null
                          ? 'Transkript bekleniyor...'
                          : 'Ses algılanmadı (Sessiz kayıt)';
                      return Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: <Widget>[
                            Icon(ic, color: const Color(0xFF94A3B8), size: 18),
                            const SizedBox(width: 10),
                            Text(
                              label,
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                color: const Color(0xFF94A3B8),
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          ],
                        ),
                      );
                    }(),
                  ),
                  // ── Notlar sekmesi ─────────────────────────────────────
                  Builder(
                    builder: (BuildContext ctx) {
                      final AppState appState = context.read<AppState>();
                      final String? aiNotes = widget.item.assistantNotes;

                      return SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: <Widget>[

                            // ── Asistan notu kartı (varsa) ─────────
                            if (aiNotes != null && aiNotes.isNotEmpty) ...<Widget>[
                              Container(
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF0FDF4),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                      color: const Color(0xFF86EFAC)),
                                ),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: <Widget>[
                                    Row(
                                      children: <Widget>[
                                        const Icon(
                                            Icons.auto_awesome_rounded,
                                            size: 13,
                                            color: Color(0xFF16A34A)),
                                        const SizedBox(width: 6),
                                        Text(
                                          'Asistan Notu',
                                          style: GoogleFonts.inter(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w700,
                                            color: const Color(0xFF16A34A),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      aiNotes,
                                      style: GoogleFonts.inter(
                                        fontSize: 13.5,
                                        height: 1.7,
                                        color: isDarkMode ? const Color(0xFFF1F5F9) : const Color(0xFF1E293B),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 14),
                            ],

                            // ── Bölüm başlığı ──────────────────────
                            Row(
                              children: <Widget>[
                                Icon(Icons.edit_note_rounded,
                                    size: 15,
                                    color: isDarkMode ? const Color(0xFF94A3B8) : const Color(0xFF64748B)),
                                const SizedBox(width: 6),
                                Text(
                                  'Kendi Notum',
                                  style: GoogleFonts.inter(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: isDarkMode ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),

                            // ── Kullanıcı metin girişi ─────────────
                            TextField(
                              controller: _noteCtrl,
                              maxLines: 8,
                              minLines: 5,
                              textAlignVertical: TextAlignVertical.top,
                              style: GoogleFonts.inter(
                                fontSize: 14,
                                height: 1.7,
                                color: isDarkMode ? const Color(0xFFF1F5F9) : const Color(0xFF1E293B),
                              ),
                              decoration: InputDecoration(
                                hintText: 'Buraya notunuzu yazın…',
                                hintStyle: GoogleFonts.inter(
                                  fontSize: 14,
                                  color: isDarkMode ? const Color(0xFF94A3B8) : const Color(0xFFCBD5E1),
                                ),
                                filled: true,
                                fillColor: const Color(0xFFF8FAFC),
                                contentPadding: const EdgeInsets.all(14),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: const BorderSide(
                                      color: Color(0xFFE2E8F0)),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: const BorderSide(
                                      color: Color(0xFFE2E8F0)),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: const BorderSide(
                                      color: Color(0xFF2563EB),
                                      width: 1.5),
                                ),
                              ),
                            ),

                            const SizedBox(height: 10),

                            // ── Kaydet butonu ──────────────────────
                            SizedBox(
                              height: 44,
                              child: ElevatedButton.icon(
                                onPressed: _isSavingNote
                                    ? null
                                    : () async {
                                        final int? id = widget.item.id;
                                        if (id == null) return;
                                        setState(() =>
                                            _isSavingNote = true);
                                        final bool ok =
                                            await appState.updateRecordNotes(
                                          id,
                                          _noteCtrl.text.trim(),
                                        );
                                        if (mounted) {
                                          setState(() =>
                                              _isSavingNote = false);
                                          ScaffoldMessenger.of(context)
                                              .showSnackBar(
                                            SnackBar(
                                              content: Text(
                                                ok
                                                    ? 'Not kaydedildi.'
                                                    : 'Kaydedilemedi, tekrar dene.',
                                              ),
                                              duration: const Duration(
                                                  seconds: 2),
                                            ),
                                          );
                                        }
                                      },
                                icon: _isSavingNote
                                    ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white,
                                        ),
                                      )
                                    : const Icon(Icons.save_rounded,
                                        size: 18),
                                label: Text(
                                  _isSavingNote
                                      ? 'Kaydediliyor…'
                                      : 'Notu Kaydet',
                                  style: GoogleFonts.inter(
                                      fontWeight: FontWeight.w700),
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor:
                                      const Color(0xFF2563EB),
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(
                                    borderRadius:
                                        BorderRadius.circular(10),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),

            // ── Sil butonu ──────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
              child: SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isDarkMode ? const Color(0xFF2D1B1B) : const Color(0xFFFEF2F2),
                    foregroundColor: const Color(0xFFEF4444),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                    side: BorderSide(color: isDarkMode ? const Color(0xFF7F1D1D) : const Color(0xFFFECACA)),
                  ),
                  icon: const Icon(Icons.delete_outline_rounded, size: 18),
                  label: Text(
                    'Kaydı Sil',
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  onPressed: widget.onDelete,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── drag handle ──────────────────────────────────────────────────────────────
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
    final bool isDarkMode = context.watch<AppState>().isDarkMode;
    return Container(
      decoration: BoxDecoration(
        color: isDarkMode ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
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
    final bool isDarkMode = context.watch<AppState>().isDarkMode;
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isDarkMode ? const Color(0xFF334155).withValues(alpha: 0.5) : iconBg.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: isDarkMode ? const Color(0xFF475569) : iconBg),
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
                      color: isDarkMode ? const Color(0xFFF1F5F9) : const Color(0xFF1E293B),
                    ),
                  ),
                  Text(
                    subtitle,
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      color: isDarkMode ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
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
    this.pendingCount = 0,
    this.onBellTap,
  });

  final String displayName;
  final String initials;
  final VoidCallback onProfileTap;
  final int pendingCount;
  final VoidCallback? onBellTap;

  @override
  Widget build(BuildContext context) {
    final bool hasBadge = pendingCount > 0;
    final String badgeText = pendingCount > 9 ? '9+' : '$pendingCount';
    final bool isDarkMode = context.watch<AppState>().isDarkMode;

    return Container(
      decoration: BoxDecoration(
        color: isDarkMode ? const Color(0xFF1E293B) : Colors.white,
        border: Border(
          bottom: BorderSide(
            color: isDarkMode ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
          ),
        ),
      ),
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
                    color: isDarkMode ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
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
                    color: isDarkMode ? const Color(0xFFF1F5F9) : const Color(0xFF1E293B),
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Row(
            children: <Widget>[
              // ── Bildirim çanı ───────────────────────────────────────────
              GestureDetector(
                onTap: onBellTap,
                behavior: HitTestBehavior.opaque,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: <Widget>[
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 250),
                      child: Icon(
                        hasBadge
                            ? Icons.notifications_active_rounded
                            : Icons.notifications_none_rounded,
                        key: ValueKey<bool>(hasBadge),
                        color: hasBadge
                            ? const Color(0xFFEF4444)
                            : const Color(0xFF94A3B8),
                        size: 24,
                      ),
                    ),
                    if (hasBadge)
                      Positioned(
                        right: -4,
                        top: -4,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          constraints: const BoxConstraints(
                              minWidth: 16, minHeight: 16),
                          padding:
                              const EdgeInsets.symmetric(horizontal: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEF4444),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Center(
                            child: Text(
                              badgeText,
                              style: GoogleFonts.inter(
                                fontSize: 8,
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // ── Dark mode toggle ────────────────────────────────────────
              Consumer<AppState>(
                builder: (BuildContext ctx, AppState state, _) =>
                    GestureDetector(
                  onTap: () => ctx.read<AppState>().toggleDarkMode(),
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: state.isDarkMode
                          ? const Color(0xFF1E293B)
                          : const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: state.isDarkMode
                            ? const Color(0xFF334155)
                            : const Color(0xFFE2E8F0),
                      ),
                    ),
                    child: Icon(
                      state.isDarkMode
                          ? Icons.light_mode_rounded
                          : Icons.dark_mode_rounded,
                      size: 18,
                      color: state.isDarkMode
                          ? const Color(0xFFFBBF24)
                          : const Color(0xFF64748B),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // ── Profil avatar ───────────────────────────────────────────
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

// ─── İstatistik satırı ────────────────────────────────────────────────────────
class _StatsRow extends StatelessWidget {
  const _StatsRow({
    required this.totalRecords,
    required this.pendingCount,
    this.isLoading = false,
  });

  final int totalRecords;
  final int pendingCount;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Expanded(
          child: _StatChip(
            icon: Icons.folder_open_rounded,
            iconColor: const Color(0xFF2563EB),
            iconBg: const Color(0xFFDBEAFE),
            label: 'Toplam Kayıt',
            value: isLoading ? null : '$totalRecords',
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _StatChip(
            icon: Icons.pending_actions_rounded,
            iconColor: pendingCount > 0
                ? const Color(0xFFF97316)
                : const Color(0xFF16A34A),
            iconBg: pendingCount > 0
                ? const Color(0xFFFFEDD5)
                : const Color(0xFFDCFCE7),
            label: 'Bekleyen',
            value: isLoading ? null : '$pendingCount',
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _StatChip(
            icon: Icons.check_circle_outline_rounded,
            iconColor: const Color(0xFF6366F1),
            iconBg: const Color(0xFFEDE9FE),
            label: 'Tamamlanan',
            value: isLoading
                ? null
                : '${totalRecords == 0 ? 0 : (totalRecords - pendingCount).clamp(0, totalRecords)}',
          ),
        ),
      ],
    );
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip({
    required this.icon,
    required this.iconColor,
    required this.iconBg,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final Color iconColor;
  final Color iconBg;
  final String label;
  final String? value; // null = yükleniyor

  @override
  Widget build(BuildContext context) {
    final bool isDarkMode = context.watch<AppState>().isDarkMode;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: isDarkMode ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDarkMode ? const Color(0xFF334155) : const Color(0xFFF1F5F9),
        ),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x060F172A),
            blurRadius: 6,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: iconBg,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 15, color: iconColor),
          ),
          const SizedBox(height: 8),
          value == null
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Color(0xFF94A3B8),
                  ),
                )
              : Text(
                  value!,
                  style: GoogleFonts.inter(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: isDarkMode ? const Color(0xFFF1F5F9) : const Color(0xFF1E293B),
                    height: 1.1,
                  ),
                ),
          const SizedBox(height: 2),
          Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 9.5,
              fontWeight: FontWeight.w600,
              color: isDarkMode ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
              letterSpacing: 0.3,
            ),
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
    final bool isDarkMode = context.watch<AppState>().isDarkMode;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isDarkMode ? const Color(0xFF1E293B) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isDarkMode ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
          ),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 8,
              offset: const Offset(0, 2),
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
                      color: isDarkMode ? const Color(0xFFF1F5F9) : const Color(0xFF1E293B),
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
  final void Function(_RecordItem item, int index) onRecordTap;

  // Solid background rengi (kart zemin)
  static Color _solidBg(String label) {
    switch (label) {
      case 'Eğitim':
        return const Color(0xFF2563EB);
      case 'Toplantı':
        return const Color(0xFF7C3AED);
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
        return Colors.white;
      case 'Toplantı':
        return Colors.white;
      case 'Röportaj':
        return Colors.white;
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
        final bool isDarkMode = ctx.watch<AppState>().isDarkMode;
        final double maxH = MediaQuery.of(ctx).size.height * 0.70;
        return Container(
          constraints: BoxConstraints(maxHeight: maxH),
          decoration: BoxDecoration(
            color: isDarkMode ? const Color(0xFF1E293B) : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
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
                          color: isDarkMode ? const Color(0xFFF1F5F9) : const Color(0xFF1E293B),
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
                            final int idx = recentItems.indexOf(item);
                            onRecordTap(item, idx);
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
            color: context.watch<AppState>().isDarkMode
                ? const Color(0xFFF1F5F9)
                : const Color(0xFF1E293B),
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

// ─── Acil Görevler (dinamik) ──────────────────────────────────────────────────
// ─────────────────────────────────────────────────────────────────────────────
// ALEV PANELİ — Aciliyet seviyesine göre dinamik kart (bugün/yarın/hafta içi)
// _parseDate / _urgencyColors / _smartDateLabel yardımcılarını kullanır.
// ─────────────────────────────────────────────────────────────────────────────

/// Görevin aciliyet kategorisi: 0=bugün, 1=yarın, 2=bu hafta, -1=uzak/tarihsiz.
/// [title] verilirse sınav/ödev/vize/final/teslim kelimelerini akademik kural
/// olarak değerlendirir: tarih 14 gün içindeyse level=2 olarak gösterir.
int _urgencyLevel(String? dueDateIso, {String? title}) {
  final DateTime? dt = _parseDate(dueDateIso);
  final bool isAcademic = title != null &&
      RegExp(r'sınav|ödev|vize|final|teslim|quiz|bütünleme',
              caseSensitive: false)
          .hasMatch(title);

  if (dt == null) return isAcademic ? 2 : -1;
  final DateTime today = DateTime(
      DateTime.now().year, DateTime.now().month, DateTime.now().day);
  final int diff =
      DateTime(dt.year, dt.month, dt.day).difference(today).inDays;
  if (diff < 0)  return 0;  // gecikmiş → bugün grubuyla göster
  if (diff == 0) return 0;  // bugün
  if (diff == 1) return 1;  // yarın
  if (diff <= 6) return 2;  // bu hafta
  if (diff <= 14 && isAcademic) return 2; // 2 hafta içi akademik görev → göster
  return -1;                // 7+ gün → gizle
}

class _UrgentTaskCard extends StatefulWidget {
  const _UrgentTaskCard({
    required this.tasks,
    required this.onViewAll,
    this.isLoading = false,
  });

  final List<_TaskItem> tasks;
  final VoidCallback onViewAll;
  final bool isLoading;

  @override
  State<_UrgentTaskCard> createState() => _UrgentTaskCardState();
}

class _UrgentTaskCardState extends State<_UrgentTaskCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseCtrl;
  late final Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 1.0, end: 1.025).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool isDarkMode = context.watch<AppState>().isDarkMode;

    if (widget.isLoading) {
      return _buildShimmer(isDarkMode);
    }

    // Sadece tamamlanmamış ve 7 gün içindeki görevler
    final List<({_TaskItem task, int level})> urgent = widget.tasks
        .where((_TaskItem t) => t.status != 'done')
        .map((_TaskItem t) => (task: t, level: _urgencyLevel(t.dueDate, title: t.title)))
        .where((r) => r.level >= 0)
        .toList()
      ..sort((a, b) => a.level.compareTo(b.level)); // en acil üste

    // Hiç acil görev yoksa boş durum kartı göster
    if (urgent.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Text('🔥', style: TextStyle(fontSize: 16)),
              const SizedBox(width: 6),
              Text(
                'Acil Görevler',
                style: GoogleFonts.inter(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: isDarkMode ? const Color(0xFFF1F5F9) : const Color(0xFF1E293B),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFFEEF2FF),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '0 görev',
                  style: GoogleFonts.inter(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF2563EB),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: const Color(0xFFE2E8F0),
                width: 1.5,
              ),
              boxShadow: const <BoxShadow>[
                BoxShadow(
                  color: Color(0x08000000),
                  blurRadius: 8,
                  offset: Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              children: <Widget>[
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: const Color(0xFFEEF2FF),
                    borderRadius: BorderRadius.circular(19),
                  ),
                  child: const Icon(
                    Icons.check_circle_outline_rounded,
                    color: Color(0xFF2563EB),
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        'Acil görev yok',
                        style: GoogleFonts.inter(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF1E293B),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Yaklaşan hatırlatman bulunmuyor.',
                        style: GoogleFonts.inter(
                          fontSize: 11.5,
                          color: const Color(0xFF94A3B8),
                        ),
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

    final int topLevel = urgent.first.level;

    // En acil görevin başlığını kart header'ına göm
    final String topTitle = urgent.first.task.title;

    // Gradient renkleri aciliyet seviyesine göre
    final List<Color> gradientColors = topLevel == 0
        ? const <Color>[Color(0xFFEF4444), Color(0xFFF97316)]
        : topLevel == 1
            ? const <Color>[Color(0xFFF97316), Color(0xFFF59E0B)]
            : const <Color>[Color(0xFF6366F1), Color(0xFF3B82F6)];

    final String emoji = topLevel == 0 ? '🔥' : topLevel == 1 ? '🟠' : '📅';
    final String urgencyLabel = topLevel == 0
        ? 'KRİTİK HATIRLATMA'
        : topLevel == 1
            ? 'DİKKAT: Yarın!'
            : 'YAKLAŞAN HATIRLATMA';
    final String urgencySubtitle = topLevel == 0
        ? 'Bugün: $topTitle'
        : topLevel == 1
            ? 'Yarın: $topTitle'
            : 'Bu Hafta: $topTitle';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            const Text('🔥', style: TextStyle(fontSize: 16)),
            const SizedBox(width: 6),
            Text(
              'Acil Görevler',
              style: GoogleFonts.inter(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: isDarkMode ? const Color(0xFFF1F5F9) : const Color(0xFF1E293B),
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: topLevel == 0
                    ? const Color(0xFFFEF2F2)
                    : topLevel == 1
                        ? const Color(0xFFFFF7ED)
                        : const Color(0xFFEEF2FF),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '${urgent.length} görev',
                style: GoogleFonts.inter(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: topLevel == 0
                      ? const Color(0xFFDC2626)
                      : topLevel == 1
                          ? const Color(0xFFEA580C)
                          : const Color(0xFF2563EB),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ScaleTransition(
      scale: _pulseAnim,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // ── 🔥 Ana gradient kart ────────────────────────────────────────────
          Container(
            margin: EdgeInsets.zero,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: gradientColors,
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(20), bottom: Radius.circular(8)),
              boxShadow: <BoxShadow>[
                BoxShadow(
                  color: gradientColors.first.withValues(alpha: 0.5),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                // Büyük emoji
                Text(emoji,
                    style: const TextStyle(fontSize: 32, height: 1.1)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        urgencyLabel,
                        style: GoogleFonts.inter(
                          color: Colors.white.withValues(alpha: 0.9),
                          fontWeight: FontWeight.w700,
                          fontSize: 11,
                          letterSpacing: 0.8,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        urgencySubtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                          height: 1.3,
                        ),
                      ),
                      if (urgent.length > 1) ...<Widget>[
                        const SizedBox(height: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.22),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '+${urgent.length - 1} hatırlatma daha',
                            style: GoogleFonts.inter(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                              fontSize: 11,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                // "Tümü" butonu
                GestureDetector(
                  onTap: widget.onViewAll,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.22),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      'Tümü →',
                      style: GoogleFonts.inter(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          // ── Kalan görevler (max 2 adet, beyaz arka plan) ────────────────────
          if (urgent.length > 1)
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: const BorderRadius.vertical(
                    bottom: Radius.circular(14)),
                // borderRadius ile Border() kenar renkleri farklı olamaz → tek renk çerçeve.
                border: Border.all(
                  color: gradientColors.first.withValues(alpha: 0.22),
                ),
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: gradientColors.first.withValues(alpha: 0.1),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Container(
                      width: 4,
                      decoration: BoxDecoration(
                        color: gradientColors.first,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    Expanded(
                      child: Column(
                        children: urgent
                            .skip(1)
                            .take(2)
                            .map((r) =>
                                _UrgentMiniRow(task: r.task, level: r.level))
                            .toList(),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
        ),
      ],
    );
  }

  Widget _buildShimmer(bool isDarkMode) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          'Acil Görevler',
          style: GoogleFonts.inter(
            fontSize: 15,
            fontWeight: FontWeight.w800,
            color: isDarkMode ? const Color(0xFFF1F5F9) : const Color(0xFF1E293B),
          ),
        ),
        const SizedBox(height: 10),
        Container(
          height: 80,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFF1F5F9)),
          ),
          child: const Center(
            child: SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: Color(0xFF2563EB),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ─── Mini satır (2. ve 3. görev için) ────────────────────────────────────────
class _UrgentMiniRow extends StatelessWidget {
  const _UrgentMiniRow({required this.task, required this.level});

  final _TaskItem task;
  final int level;

  @override
  Widget build(BuildContext context) {
    final Color accent = level == 0
        ? const Color(0xFFDC2626)
        : level == 1
            ? const Color(0xFFEA580C)
            : const Color(0xFF2563EB);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      child: Row(
        children: <Widget>[
          Icon(Icons.circle, size: 6, color: accent),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              task.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF334155),
              ),
            ),
          ),
          if (task.dueDate != null)
            Text(
              _smartDateLabel(_parseDate(task.dueDate)!),
              style: GoogleFonts.inter(
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                color: accent,
              ),
            ),
        ],
      ),
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
    this.isInitialLoading = false,
  });

  final bool isLoading;
  final bool isInitialLoading;
  final String currentFileName;
  final String currentCategory;
  final List<_RecordItem> recentItems;
  final void Function(_RecordItem item, int index) onRecordTap;

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
            color: context.watch<AppState>().isDarkMode
                ? const Color(0xFFF1F5F9)
                : const Color(0xFF1E293B),
          ),
        ),
        const SizedBox(height: 10),
        // Dosya yükleme / dönüştürme kartı
        if (isLoading) ...<Widget>[
          _ConvertingCard(
            fileName: currentFileName,
            category: currentCategory,
          ),
          const SizedBox(height: 10),
        ],
        // İlk API yüklemesi devam ediyor ve henüz kayıt yok
        if (isInitialLoading && recentItems.isEmpty)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFF1F5F9)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.4,
                    color: Color(0xFF2563EB),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  'Analiz ediliyor...',
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF2563EB),
                  ),
                ),
              ],
            ),
          )
        else if (recentItems.isEmpty && !isLoading)
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
          ...recentItems.asMap().entries.map((MapEntry<int, _RecordItem> e) =>
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _DynamicRecordCard(
                    item: e.value,
                    onTap: () => onRecordTap(e.value, e.key),
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
String _stripExt(String name) {
  final int dot = name.lastIndexOf('.');
  return dot > 0 ? name.substring(0, dot) : name;
}

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

    final bool isDarkMode = context.watch<AppState>().isDarkMode;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isDarkMode ? const Color(0xFF334155) : const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isDarkMode ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
          ),
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
                  // Başlık — 3 durum:
                  //   null → "Transkript bekleniyor..."
                  //   ""   → "Ses algılanmadı (Sessiz kayıt)"
                  //   metin → özet (ilk 40 karakter)
                  Builder(
                    builder: (_) {
                      final String? t = item.transcript;
                      if (t == null) {
                        return Text(
                          'Transkript bekleniyor...',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFF94A3B8),
                          ),
                        );
                      }
                      if (t.trim().isEmpty) {
                        return Text(
                          'Ses algılanmadı (Sessiz kayıt)',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            fontStyle: FontStyle.italic,
                            color: const Color(0xFFB0BEC5),
                          ),
                        );
                      }
                      final String preview = item.autoTitle?.isNotEmpty == true
                          ? item.autoTitle!
                          : item.fileName;
                      return Text(
                        preview,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: isDarkMode
                              ? const Color(0xFFF1F5F9)
                              : const Color(0xFF1E293B),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 3),
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
                      // Alt başlık: tarih
                      Expanded(
                        child: Text(
                          _recordDateLabelStatic(item.createdAt),
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

// ─── Top-level tarih yardımcısı (widget dışında kullanılır) ──────────────────
String _recordDateLabelStatic(DateTime? dt) {
  if (dt == null) return '';
  final DateTime now = DateTime.now();
  final DateTime today = DateTime(now.year, now.month, now.day);
  final int diff = today.difference(DateTime(dt.year, dt.month, dt.day)).inDays;
  if (diff == 0) {
    return 'Bugün · ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
  if (diff == 1) return 'Dün';
  const List<String> months = <String>[
    'Oca', 'Şub', 'Mar', 'Nis', 'May', 'Haz',
    'Tem', 'Ağu', 'Eyl', 'Eki', 'Kas', 'Ara',
  ];
  return '${dt.day} ${months[dt.month - 1]}';
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
    final bool isDarkMode = context.watch<AppState>().isDarkMode;
    return Container(
      height: 84,
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 22),
      decoration: BoxDecoration(
        color: isDarkMode ? const Color(0xFF1E293B) : Colors.white,
        border: Border(
          top: BorderSide(
            color: isDarkMode ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
          ),
        ),
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
            label: 'Aksiyonlar',
            icon: Icons.bolt_rounded,
            selected: selectedIndex == 1,
            onTap: () => onTap(1),
          ),
          const SizedBox(width: 64), // FAB için boşluk
          _NavItem(
            label: 'Takvim',
            icon: Icons.calendar_month_rounded,
            selected: selectedIndex == 2,
            onTap: () => onTap(2),
          ),
          _NavItem(
            label: 'Kayıtlar',
            icon: Icons.folder_open_rounded,
            selected: selectedIndex == 3,
            onTap: () => onTap(3),
          ),
          _NavItem(
            label: 'Profil',
            icon: Icons.person_outline_rounded,
            selected: false,
            onTap: () => onTap(4),
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
