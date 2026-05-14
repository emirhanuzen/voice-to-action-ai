import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:table_calendar/table_calendar.dart';

import '../state/app_state.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Seçilen günde yapılandırılmış aksiyon yoksa: transkriptte o tarihin geçtiği cümleler
// (Whisper hataları için ay adı varyantları + gün sayısı sınırı).
// ─────────────────────────────────────────────────────────────────────────────

class _TranscriptDayHit {
  const _TranscriptDayHit({
    required this.recordId,
    required this.snippet,
    required this.title,
  });

  final int recordId;
  final String snippet;
  final String title;
}

String _foldTrAscii(String s) {
  return s
      .toLowerCase()
      .replaceAll('ı', 'i')
      .replaceAll('ğ', 'g')
      .replaceAll('ü', 'u')
      .replaceAll('ş', 's')
      .replaceAll('ö', 'o')
      .replaceAll('ç', 'c')
      .replaceAll('â', 'a')
      .replaceAll('î', 'i')
      .replaceAll('û', 'u');
}

/// Her ay için Whisper’da sık bozulan yazılışlar (küçük harf yeterli; eşlemede fold uygulanır).
const List<List<String>> _kMonthAliases = <List<String>>[
  <String>['ocak', 'ocag', 'okak', 'ojak', 'ucak', 'oçak', 'ocac'],
  <String>['şubat', 'subat', 'şubad', 'subad', 'shubat'],
  <String>['mart', 'mard', 'martt'],
  <String>['nisan', 'nizan', 'nişan', 'nisamn', 'nissan', 'nizam'],
  <String>[
    'mayıs', 'mayis', 'meis', 'mais', 'mays', 'meyis', 'mayış', 'mayız',
    'mayyıs', 'mayes', 'mayiss', 'meiss', 'meiş', 'maıs',
  ],
  <String>['haziran', 'haziram', 'hazıram', 'haziron', 'hazran', 'haziiran'],
  <String>['temmuz', 'temuz', 'temmüz', 'temüz', 'temmus'],
  <String>['ağustos', 'agustos', 'augustos', 'ağıstos', 'ağusdos', 'ağustus'],
  <String>['eylül', 'eylul', 'aylül', 'aylul', 'eylull'],
  <String>['ekim', 'ekım', 'ekimm', 'akim'],
  <String>['kasım', 'kasim', 'kasem', 'qasım', 'qasim', 'casım', 'casim'],
  <String>['aralık', 'aralik', 'arali', 'aralı', 'araliq', 'arlık', 'aralig'],
];

bool _hasStandaloneDay(String foldedSentence, int day) {
  final String ds = day.toString();
  return RegExp(r'(^|[^0-9])' + RegExp.escape(ds) + r'([^0-9]|$)')
      .hasMatch(foldedSentence);
}

bool _hasMonthForDay(String foldedSentence, DateTime day) {
  final int idx = day.month - 1;
  if (idx < 0 || idx >= _kMonthAliases.length) return false;
  for (final String a in _kMonthAliases[idx]) {
    if (foldedSentence.contains(_foldTrAscii(a))) return true;
  }
  return false;
}

bool _hasIsoStyleDate(String text, DateTime day) {
  final String y = day.year.toString();
  final String m = day.month.toString().padLeft(2, '0');
  final String d = day.day.toString().padLeft(2, '0');
  final String t = text.toLowerCase();
  return t.contains('$y-$m-$d') ||
      t.contains('$d.$m.$y') ||
      t.contains('$d/$m/$y') ||
      t.contains('$d-$m-$y');
}

bool _sentenceReferencesCalendarDay(String sentence, DateTime day) {
  final String folded = _foldTrAscii(sentence);
  if (_hasIsoStyleDate(sentence, day)) return true;
  if (!_hasStandaloneDay(folded, day.day)) return false;
  return _hasMonthForDay(folded, day);
}

List<String> _splitSentences(String text) {
  return text
      .split(RegExp(r'(?<=[.!?…])\s+|(?<=\n)\s*'))
      .map((String s) => s.trim())
      .where((String s) => s.isNotEmpty)
      .toList();
}

String _clipSnippet(String s, {int maxLen = 240}) {
  final String t = s.trim();
  if (t.length <= maxLen) return t;
  return '${t.substring(0, maxLen - 1)}…';
}

List<_TranscriptDayHit> _transcriptHitsForDay(
    DateTime day, List<RecordItem> records) {
  final List<_TranscriptDayHit> out = <_TranscriptDayHit>[];
  for (final RecordItem r in records) {
    final int? id = r.id;
    if (id == null) continue;
    final String? raw = r.transcript;
    if (raw == null || raw.trim().isEmpty) continue;

    final List<String> parts = _splitSentences(raw);
    String? hit;
    for (final String s in parts) {
      if (_sentenceReferencesCalendarDay(s, day)) {
        hit = s;
        break;
      }
    }
    if (hit == null && _sentenceReferencesCalendarDay(raw, day)) {
      hit = raw;
    }
    if (hit == null) continue;

    final String title = (r.autoTitle != null && r.autoTitle!.trim().isNotEmpty)
        ? r.autoTitle!.trim()
        : r.fileName;

    out.add(_TranscriptDayHit(
      recordId: id,
      snippet: _clipSnippet(hit),
      title: title,
    ));
  }
  return out;
}

// ─────────────────────────────────────────────────────────────────────────────
// Takvim Ekranı
// ─────────────────────────────────────────────────────────────────────────────
class CalendarScreen extends StatefulWidget {
  const CalendarScreen({
    super.key,
    this.initialDate,
    this.onNavigateToTask,
    this.onOpenRecord,
  });

  static const String routeName = '/calendar';

  /// Aksiyonlar sekmesindeki tarih rozetinden gelince açılacak gün.
  final DateTime? initialDate;

  /// Takvim görev kartı "Aksiyonlarda Göster" → aksiyonlar sekmesinde vurgula.
  final void Function(int taskId)? onNavigateToTask;

  /// Takvim görev kartı "Kaydı Aç" → Kayıtlar sekmesine git + detay aç.
  final void Function(int recordId)? onOpenRecord;

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _fadeCtrl;
  late final Animation<double> _fadeAnim;

  late DateTime _focusedDay;
  late DateTime _selectedDay;

  // Ay görünümü varsayılan — daha büyük ve okunaklı
  CalendarFormat _calendarFormat = CalendarFormat.month;

  @override
  void initState() {
    super.initState();
    final DateTime jump = widget.initialDate ?? DateTime.now();
    _focusedDay = jump;
    _selectedDay = jump;
    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    )..forward();
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    super.dispose();
  }

  DateTime? _parseTaskDate(String? iso) {
    if (iso == null || iso.isEmpty) return null;
    try {
      return DateTime.parse(iso);
    } catch (_) {
      return null;
    }
  }

  List<TaskItem> _tasksForDay(List<TaskItem> all, DateTime day) {
    final DateTime d = DateTime(day.year, day.month, day.day);
    return all.where((TaskItem t) {
      final DateTime? dt = _parseTaskDate(t.dueDate);
      if (dt == null) return false;
      return DateTime(dt.year, dt.month, dt.day) == d;
    }).toList();
  }

  Color _urgencyColor(DateTime day) {
    final DateTime today = DateTime(
        DateTime.now().year, DateTime.now().month, DateTime.now().day);
    final int diff =
        DateTime(day.year, day.month, day.day).difference(today).inDays;
    if (diff < 0) return const Color(0xFFEF4444);
    if (diff == 0) return const Color(0xFFEF4444);
    if (diff == 1) return const Color(0xFFF97316);
    if (diff <= 6) return const Color(0xFF2563EB);
    return const Color(0xFF94A3B8);
  }

  String _humanDate(DateTime d) {
    const List<String> months = <String>[
      'Ocak', 'Şubat', 'Mart', 'Nisan', 'Mayıs', 'Haziran',
      'Temmuz', 'Ağustos', 'Eylül', 'Ekim', 'Kasım', 'Aralık',
    ];
    const List<String> days = <String>[
      'Pazartesi', 'Salı', 'Çarşamba', 'Perşembe', 'Cuma',
      'Cumartesi', 'Pazar',
    ];
    final DateTime today = DateTime(
        DateTime.now().year, DateTime.now().month, DateTime.now().day);
    final int diff =
        DateTime(d.year, d.month, d.day).difference(today).inDays;
    if (diff == 0) return 'Bugün';
    if (diff == 1) return 'Yarın';
    if (diff == -1) return 'Dün';
    return '${days[d.weekday - 1]}, ${d.day} ${months[d.month - 1]}';
  }

  @override
  Widget build(BuildContext context) {
    final AppState appState = context.watch<AppState>();
    final List<TaskItem> allTasks = appState.tasks;
    final List<TaskItem> dayTasks = _tasksForDay(allTasks, _selectedDay);
    final List<_TranscriptDayHit> transcriptHits = dayTasks.isEmpty
        ? _transcriptHitsForDay(_selectedDay, appState.records)
        : <_TranscriptDayHit>[];
    final Color urgColor = _urgencyColor(_selectedDay);
    final bool isDarkMode = appState.isDarkMode;

    return Scaffold(
      backgroundColor: isDarkMode ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
      body: SafeArea(
        child: FadeTransition(
          opacity: _fadeAnim,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              // ── Başlık ──────────────────────────────────────────────────────
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                child: Row(
                  children: <Widget>[
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: <Color>[Color(0xFF2563EB), Color(0xFF4F46E5)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: const <BoxShadow>[
                          BoxShadow(
                            color: Color(0x402563EB),
                            blurRadius: 10,
                            offset: Offset(0, 4),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.calendar_month_rounded,
                        color: Colors.white,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            'Takvim',
                            style: GoogleFonts.inter(
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                              color: isDarkMode ? const Color(0xFFF1F5F9) : const Color(0xFF1E293B),
                            ),
                          ),
                          Text(
                            'Aksiyonlarını takip et',
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              color: const Color(0xFF64748B),
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Format toggler
                    GestureDetector(
                      onTap: () => setState(() {
                        _calendarFormat =
                            _calendarFormat == CalendarFormat.month
                                ? CalendarFormat.week
                                : CalendarFormat.month;
                        _fadeCtrl
                          ..reset()
                          ..forward();
                      }),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 7),
                        decoration: BoxDecoration(
                          color: isDarkMode ? const Color(0xFF334155) : const Color(0xFFEFF6FF),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isDarkMode ? const Color(0xFF475569) : const Color(0xFFBFDBFE),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            Icon(
                              _calendarFormat == CalendarFormat.month
                                  ? Icons.view_week_rounded
                                  : Icons.calendar_view_month_rounded,
                              size: 14,
                              color: isDarkMode ? const Color(0xFF93C5FD) : const Color(0xFF2563EB),
                            ),
                            const SizedBox(width: 5),
                            Text(
                              _calendarFormat == CalendarFormat.month
                                  ? 'Haftalık'
                                  : 'Aylık',
                              style: GoogleFonts.inter(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: isDarkMode ? const Color(0xFF93C5FD) : const Color(0xFF2563EB),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // ── Takvim kartı ─────────────────────────────────────────────
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: isDarkMode ? const Color(0xFF1E293B) : Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: <BoxShadow>[
                    BoxShadow(
                      color: isDarkMode
                          ? const Color(0xFF000000).withValues(alpha: 0.3)
                          : Colors.black.withValues(alpha: 0.06),
                      blurRadius: 16,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: TableCalendar<TaskItem>(
                  firstDay: DateTime.utc(2024, 1, 1),
                  lastDay: DateTime.utc(2027, 12, 31),
                  focusedDay: _focusedDay,
                  calendarFormat: _calendarFormat,
                  selectedDayPredicate: (DateTime day) =>
                      isSameDay(day, _selectedDay),
                  eventLoader: (DateTime day) => _tasksForDay(allTasks, day),
                  startingDayOfWeek: StartingDayOfWeek.monday,
                  rowHeight: 52,
                  onDaySelected: (DateTime selected, DateTime focused) {
                    setState(() {
                      _selectedDay = selected;
                      _focusedDay = focused;
                    });
                    _fadeCtrl
                      ..reset()
                      ..forward();
                  },
                  onFormatChanged: (CalendarFormat fmt) =>
                      setState(() => _calendarFormat = fmt),
                  onPageChanged: (DateTime focused) =>
                      setState(() => _focusedDay = focused),
                  calendarBuilders: CalendarBuilders<TaskItem>(
                    markerBuilder: (BuildContext ctx, DateTime day,
                        List<TaskItem> events) {
                      if (events.isEmpty) return const SizedBox.shrink();
                      final DateTime today = DateTime(DateTime.now().year,
                          DateTime.now().month, DateTime.now().day);
                      final int diff =
                          DateTime(day.year, day.month, day.day)
                              .difference(today)
                              .inDays;
                      final int pending = events
                          .where((TaskItem t) => t.status != 'done')
                          .length;

                      String emoji;
                      if (pending == 0) {
                        emoji = '✅';
                      } else if (diff < 0) {
                        emoji = '⚠️';
                      } else if (diff == 0) {
                        emoji = '🔥';
                      } else if (diff == 1) {
                        emoji = '⏰';
                      } else if (diff <= 6) {
                        emoji = '📌';
                      } else {
                        emoji = '📅';
                      }

                      return Positioned(
                        bottom: 3,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            Text(emoji,
                                style: const TextStyle(
                                    fontSize: 11, height: 1)),
                            if (events.length > 1)
                              Container(
                                margin: const EdgeInsets.only(left: 2),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 4, vertical: 1),
                                decoration: BoxDecoration(
                                  color: pending == 0
                                      ? const Color(0xFF16A34A)
                                      : _urgencyColor(day),
                                  borderRadius: BorderRadius.circular(5),
                                ),
                                child: Text(
                                  '${events.length}',
                                  style: const TextStyle(
                                    fontSize: 8,
                                    color: Colors.white,
                                    fontWeight: FontWeight.w800,
                                    height: 1.3,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      );
                    },
                  ),
                  calendarStyle: CalendarStyle(
                    outsideDaysVisible: false,
                    cellMargin: const EdgeInsets.all(5),
                    defaultDecoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      shape: BoxShape.rectangle,
                    ),
                    weekendDecoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      shape: BoxShape.rectangle,
                    ),
                    outsideDecoration: const BoxDecoration(
                      shape: BoxShape.rectangle,
                    ),
                    todayDecoration: BoxDecoration(
                      color: isDarkMode ? const Color(0xFF1E3A5F) : const Color(0xFFDBEAFE),
                      borderRadius: BorderRadius.circular(10),
                      shape: BoxShape.rectangle,
                    ),
                    todayTextStyle: GoogleFonts.inter(
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                      color: isDarkMode ? const Color(0xFF3B82F6) : const Color(0xFF2563EB),
                    ),
                    selectedDecoration: BoxDecoration(
                      color: const Color(0xFF2563EB),
                      borderRadius: BorderRadius.circular(10),
                      shape: BoxShape.rectangle,
                      boxShadow: const <BoxShadow>[
                        BoxShadow(
                          color: Color(0x402563EB),
                          blurRadius: 6,
                          offset: Offset(0, 3),
                        ),
                      ],
                    ),
                    selectedTextStyle: GoogleFonts.inter(
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                      color: Colors.white,
                    ),
                    defaultTextStyle: GoogleFonts.inter(
                      fontSize: 13,
                      color: isDarkMode ? const Color(0xFFF1F5F9) : const Color(0xFF1E293B),
                    ),
                    weekendTextStyle: GoogleFonts.inter(
                      fontSize: 13,
                      color: const Color(0xFF94A3B8),
                    ),
                  ),
                  headerStyle: HeaderStyle(
                    formatButtonVisible: false,
                    titleCentered: true,
                    titleTextStyle: GoogleFonts.inter(
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                      color: isDarkMode ? const Color(0xFFF1F5F9) : const Color(0xFF1E293B),
                    ),
                    leftChevronIcon: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.chevron_left_rounded,
                        color: Color(0xFF2563EB),
                        size: 18,
                      ),
                    ),
                    rightChevronIcon: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.chevron_right_rounded,
                        color: Color(0xFF2563EB),
                        size: 18,
                      ),
                    ),
                    headerPadding:
                        const EdgeInsets.fromLTRB(12, 14, 12, 10),
                  ),
                  daysOfWeekStyle: DaysOfWeekStyle(
                    weekdayStyle: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: isDarkMode ? const Color(0xFF94A3B8) : const Color(0xFF1E293B),
                    ),
                    weekendStyle: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF64748B),
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // ── Seçili gün başlığı ───────────────────────────────────────
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: <Widget>[
                    Container(
                      width: 6,
                      height: 20,
                      decoration: BoxDecoration(
                        color: urgColor,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _humanDate(_selectedDay),
                        style: GoogleFonts.inter(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: isDarkMode ? const Color(0xFFF1F5F9) : const Color(0xFF1E293B),
                        ),
                      ),
                    ),
                    if (dayTasks.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: urgColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(10),
                          border:
                              Border.all(color: urgColor.withValues(alpha: 0.3)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            Icon(Icons.task_alt_rounded,
                                size: 12, color: urgColor),
                            const SizedBox(width: 4),
                            Text(
                              '${dayTasks.length} aksiyon',
                              style: GoogleFonts.inter(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: urgColor,
                              ),
                            ),
                          ],
                        ),
                      )
                    else if (transcriptHits.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFF7C3AED).withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                              color: const Color(0xFF7C3AED)
                                  .withValues(alpha: 0.35)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            const Icon(Icons.subtitles_outlined,
                                size: 12, color: Color(0xFF7C3AED)),
                            const SizedBox(width: 4),
                            Text(
                              '${transcriptHits.length} kayıt metni',
                              style: GoogleFonts.inter(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: const Color(0xFF7C3AED),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),

              const SizedBox(height: 10),

              // ── Görev / transkript listesi ───────────────────────────────
              Expanded(
                child: dayTasks.isNotEmpty
                    ? ListView.separated(
                        padding:
                            const EdgeInsets.fromLTRB(16, 0, 16, 100),
                        itemCount: dayTasks.length,
                        separatorBuilder:
                            (BuildContext context, int index) =>
                            const SizedBox(height: 10),
                        itemBuilder: (BuildContext context, int i) =>
                            _CalendarTaskCard(
                          task: dayTasks[i],
                          urgencyColor: urgColor,
                          onToggle: () async {
                            final int idx = appState.tasks
                                .indexWhere((t) => t.id == dayTasks[i].id);
                            if (idx != -1) {
                              await appState.toggleTask(idx);
                            }
                          },
                          onNavigateToTask:
                              widget.onNavigateToTask != null &&
                                      dayTasks[i].id != null
                                  ? () => widget
                                      .onNavigateToTask!(dayTasks[i].id!)
                                  : null,
                          onOpenRecord:
                              widget.onOpenRecord != null &&
                                      dayTasks[i].recordId != null
                                  ? () => widget
                                      .onOpenRecord!(dayTasks[i].recordId!)
                                  : null,
                        ),
                      )
                    : transcriptHits.isNotEmpty
                        ? ListView.builder(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                            itemCount: transcriptHits.length + 1,
                            itemBuilder: (BuildContext context, int index) {
                              if (index == 0) {
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 14),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: <Widget>[
                                      Text(
                                        'Bu tarih için yapılandırılmış aksiyon yok',
                                        style: GoogleFonts.inter(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w800,
                                          color: const Color(0xFF1E293B),
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        'Kayıtlardaki konuşmada bu gün geçen cümleler '
                                        'aşağıda. İstersen kaydı açıp transkripti '
                                        'görebilirsin.',
                                        style: GoogleFonts.inter(
                                          fontSize: 12,
                                          height: 1.45,
                                          color: const Color(0xFF64748B),
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              }
                              final _TranscriptDayHit h =
                                  transcriptHits[index - 1];
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: _TranscriptHitCard(
                                  hit: h,
                                  onOpenRecord: widget.onOpenRecord != null
                                      ? () => widget.onOpenRecord!(h.recordId)
                                      : null,
                                ),
                              );
                            },
                          )
                        : _EmptyDayView(day: _selectedDay),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Transkriptten gelen “bu gün” satırı ─────────────────────────────────────
class _TranscriptHitCard extends StatelessWidget {
  const _TranscriptHitCard({
    required this.hit,
    this.onOpenRecord,
  });

  final _TranscriptDayHit hit;
  final VoidCallback? onOpenRecord;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE2E8F0)),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEDE9FE),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.format_quote_rounded,
                    size: 16,
                    color: Color(0xFF6366F1),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    hit.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF64748B),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              hit.snippet,
              style: GoogleFonts.inter(
                fontSize: 14,
                height: 1.45,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF1E293B),
              ),
            ),
            if (onOpenRecord != null) ...<Widget>[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: onOpenRecord,
                  icon: const Icon(Icons.play_circle_outline_rounded, size: 18),
                  label: Text(
                    'Kaydı Aç',
                    style: GoogleFonts.inter(fontWeight: FontWeight.w700),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF6366F1),
                    side: const BorderSide(color: Color(0xFF6366F1)),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ─── Boş gün görünümü ─────────────────────────────────────────────────────────
class _EmptyDayView extends StatelessWidget {
  const _EmptyDayView({required this.day});

  final DateTime day;

  @override
  Widget build(BuildContext context) {
    final bool isDarkMode = context.watch<AppState>().isDarkMode;
    final bool isPast = day.isBefore(DateTime(
        DateTime.now().year, DateTime.now().month, DateTime.now().day));

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: isDarkMode ? const Color(0xFF334155) : const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(40),
            ),
            child: Icon(
              isPast
                  ? Icons.event_available_rounded
                  : Icons.event_note_rounded,
              size: 36,
              color: const Color(0xFF94A3B8),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            isPast ? 'Bu gün için kayıt yok' : 'Bu gün için metin eşleşmesi yok',
            style: GoogleFonts.inter(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: isDarkMode ? const Color(0xFF94A3B8) : const Color(0xFF475569),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            isPast
                ? 'Geçmiş bir tarih seçtiniz.'
                : 'Kayıtlarda bu tarih (gün + ay) geçmiyorsa burada\nbir şey görünmez. Aksiyonlar sekmesinden de kontrol edebilirsin.',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              fontSize: 12.5,
              color: const Color(0xFF64748B),
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Takvim görev kartı ───────────────────────────────────────────────────────
class _CalendarTaskCard extends StatelessWidget {
  const _CalendarTaskCard({
    required this.task,
    required this.urgencyColor,
    required this.onToggle,
    this.onNavigateToTask,
    this.onOpenRecord,
  });

  final TaskItem task;
  final Color urgencyColor;
  final VoidCallback onToggle;
  final VoidCallback? onNavigateToTask;
  final VoidCallback? onOpenRecord;

  @override
  Widget build(BuildContext context) {
    final bool isDarkMode = context.watch<AppState>().isDarkMode;
    final bool isDone = task.status == 'done';
    final bool isUrgent = !isDone &&
        (urgencyColor == const Color(0xFFFF006E) ||
            urgencyColor == const Color(0xFFFF6B00));

    return Stack(
      clipBehavior: Clip.none,
      children: <Widget>[
        AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
          padding: const EdgeInsets.fromLTRB(12, 14, 14, 14),
          decoration: BoxDecoration(
            color: isDone
                ? (isDarkMode ? const Color(0xFF1A2535) : const Color(0xFFF8FAFC))
                : (isDarkMode ? const Color(0xFF1E293B) : Colors.white),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: isDone
                  ? const Color(0xFFE2E8F0)
                  : urgencyColor.withValues(alpha: 0.22),
            ),
            boxShadow: isDone
                ? const <BoxShadow>[]
                : <BoxShadow>[
                    BoxShadow(
                      color: urgencyColor.withValues(alpha: 0.08),
                      blurRadius: 12,
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
                  margin: const EdgeInsets.only(right: 10),
                  decoration: BoxDecoration(
                    color: isDone ? const Color(0xFFE2E8F0) : urgencyColor,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              // ── Checkbox ──────────────────────────────────────────────────
              GestureDetector(
                onTap: onToggle,
                behavior: HitTestBehavior.opaque,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: isDone
                        ? const Color(0xFFDCFCE7)
                        : urgencyColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    child: Icon(
                      isDone
                          ? Icons.check_circle_rounded
                          : Icons.radio_button_unchecked_rounded,
                      key: ValueKey<bool>(isDone),
                      color: isDone ? const Color(0xFF16A34A) : urgencyColor,
                      size: 22,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // ── İçerik ────────────────────────────────────────────────────
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    AnimatedDefaultTextStyle(
                      duration: const Duration(milliseconds: 200),
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: isDone
                            ? const Color(0xFFCBD5E1)
                            : (isDarkMode ? const Color(0xFFF1F5F9) : const Color(0xFF1E293B)),
                        height: 1.4,
                        decoration: isDone
                            ? TextDecoration.lineThrough
                            : TextDecoration.none,
                        decorationColor: const Color(0xFFCBD5E1),
                        decorationThickness: 1.5,
                      ),
                      child: Text(task.title,
                          maxLines: 3, overflow: TextOverflow.ellipsis),
                    ),
                    const SizedBox(height: 8),
                    // ── Rozetler satırı ─────────────────────────────────────
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: <Widget>[
                        // AI hatırlatma rozeti
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 3),
                          decoration: BoxDecoration(
                            color: isDone
                                ? const Color(0xFFF1F5F9)
                                : urgencyColor.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              Icon(
                                Icons.auto_awesome_rounded,
                                size: 10,
                                color: isDone
                                    ? const Color(0xFFCBD5E1)
                                    : urgencyColor,
                              ),
                              const SizedBox(width: 3),
                              Text(
                                'AI Aksiyon',
                                style: GoogleFonts.inter(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: isDone
                                      ? const Color(0xFFCBD5E1)
                                      : urgencyColor,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (isDone)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 7, vertical: 3),
                            decoration: BoxDecoration(
                              color: const Color(0xFFDCFCE7),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: <Widget>[
                                const Icon(Icons.check_rounded,
                                    size: 10,
                                    color: Color(0xFF16A34A)),
                                const SizedBox(width: 3),
                                Text(
                                  'Tamamlandı',
                                  style: GoogleFonts.inter(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    color: const Color(0xFF16A34A),
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                    // ── Aksiyon butonları ────────────────────────────────────
                    if (onOpenRecord != null || onNavigateToTask != null) ...<Widget>[
                      const SizedBox(height: 10),
                      Row(
                        children: <Widget>[
                          // Kaydı Aç butonu
                          if (onOpenRecord != null)
                            Expanded(
                              child: GestureDetector(
                                onTap: onOpenRecord,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      vertical: 7),
                                  decoration: BoxDecoration(
                                    color: isDarkMode
                                        ? const Color(0xFF1E3A5F)
                                        : const Color(0xFFEFF6FF),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                        color: isDarkMode
                                            ? const Color(0xFF3B82F6).withValues(alpha: 0.3)
                                            : const Color(0xFFBFDBFE)),
                                  ),
                                  child: Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.center,
                                    children: <Widget>[
                                      Icon(Icons.play_circle_outline_rounded,
                                          size: 13,
                                          color: isDarkMode
                                              ? const Color(0xFF93C5FD)
                                              : const Color(0xFF2563EB)),
                                      const SizedBox(width: 5),
                                      Text(
                                        'Kaydı Aç',
                                        style: GoogleFonts.inter(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700,
                                          color: isDarkMode
                                              ? const Color(0xFF93C5FD)
                                              : const Color(0xFF2563EB),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          if (onOpenRecord != null && onNavigateToTask != null)
                            const SizedBox(width: 6),
                          // Aksiyonlarda Göster butonu
                          if (onNavigateToTask != null)
                            Expanded(
                              child: GestureDetector(
                                onTap: onNavigateToTask,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      vertical: 7),
                                  decoration: BoxDecoration(
                                    color: isDarkMode
                                        ? const Color(0xFF334155)
                                        : const Color(0xFFF1F5F9),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                        color: isDarkMode
                                            ? const Color(0xFF475569)
                                            : const Color(0xFFE2E8F0)),
                                  ),
                                  child: Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.center,
                                    children: <Widget>[
                                      Icon(
                                          Icons.format_list_bulleted_rounded,
                                          size: 12,
                                          color: isDarkMode
                                              ? const Color(0xFFF1F5F9)
                                              : const Color(0xFF475569)),
                                      const SizedBox(width: 5),
                                      Text(
                                        'Listede Göster',
                                        style: GoogleFonts.inter(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700,
                                          color: isDarkMode
                                              ? const Color(0xFFF1F5F9)
                                              : const Color(0xFF475569),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
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
          ),
        ),
        if (isUrgent)
          const Positioned(
            top: -6,
            right: 10,
            child: Text('🔥', style: TextStyle(fontSize: 18)),
          ),
      ],
    );
  }
}
