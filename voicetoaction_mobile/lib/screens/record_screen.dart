import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';

import '../services/api_service.dart';

// ─── Kategori verisi ──────────────────────────────────────────────────────────
class _Cat {
  const _Cat(this.emoji, this.label, this.color, this.bg);
  final String emoji;
  final String label;
  final Color color;
  final Color bg;
}

const List<_Cat> _kCats = <_Cat>[
  _Cat('🎓', 'Eğitim',   Color(0xFF3B82F6), Color(0xFFDBEAFE)),
  _Cat('💼', 'Toplantı', Color(0xFF7C3AED), Color(0xFFEDE9FE)),
  _Cat('🎤', 'Röportaj', Color(0xFFF59E0B), Color(0xFFFEF3C7)),
  _Cat('👤', 'Kişisel',  Color(0xFF10B981), Color(0xFFD1FAE5)),
  _Cat('📁', 'Diğer',    Color(0xFF64748B), Color(0xFFF1F5F9)),
];

// ═══════════════════════════════════════════════════════════════════════════════
// ANA EKRAN
// ═══════════════════════════════════════════════════════════════════════════════
class RecordScreen extends StatefulWidget {
  const RecordScreen({super.key});
  static const String routeName = '/record';

  @override
  State<RecordScreen> createState() => _RecordScreenState();
}

class _RecordScreenState extends State<RecordScreen>
    with SingleTickerProviderStateMixin {
  // ── Servisler ──────────────────────────────────────────────────────────────
  final AudioRecorder _recorder = AudioRecorder();
  final ApiService _apiService = ApiService();

  // ── UI durumu ──────────────────────────────────────────────────────────────
  int _selectedCat = 0;
  bool _isRecording = false;
  bool _isUploading = false;
  int _elapsedSeconds = 0;
  Timer? _timer;
  String? _recordedPath; // kayıt bittikten sonra dosya yolu

  // ── Pulse animasyonu ───────────────────────────────────────────────────────
  late final AnimationController _pulseCtrl;
  late final Animation<double> _pulseAnim;

  // ── Kısayollar ─────────────────────────────────────────────────────────────
  _Cat get _cat => _kCats[_selectedCat];
  bool get _hasStopped => _recordedPath != null && !_isRecording;

  String get _formattedTime {
    final int m = _elapsedSeconds ~/ 60;
    final int s = _elapsedSeconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  // ── Init / Dispose ─────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _pulseAnim = Tween<double>(begin: 1.0, end: 1.18).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    _recorder.dispose();
    _pulseCtrl.dispose();
    super.dispose();
  }

  // ── Kayıt başlat ──────────────────────────────────────────────────────────
  Future<void> _startRecording() async {
    // Mikrofon izni
    final PermissionStatus status = await Permission.microphone.request();
    if (!status.isGranted) {
      if (!mounted) return;
      _snack('Mikrofon izni verilmedi. Lütfen ayarlardan izin verin.',
          error: true);
      return;
    }

    try {
      final Directory tmp = await getTemporaryDirectory();
      final String path =
          '${tmp.path}/vta_${DateTime.now().millisecondsSinceEpoch}.m4a';

      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 128000,
          sampleRate: 44100,
          numChannels: 1,
        ),
        path: path,
      );

      _elapsedSeconds = 0;
      _timer =
          Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() => _elapsedSeconds++);
      });
      _pulseCtrl.repeat(reverse: true);

      setState(() {
        _isRecording = true;
        _recordedPath = null;
      });
    } catch (e) {
      if (!mounted) return;
      _snack('Kayıt başlatılamadı: $e', error: true);
    }
  }

  // ── Kayıt durdur ──────────────────────────────────────────────────────────
  Future<void> _stopRecording() async {
    _timer?.cancel();
    _pulseCtrl
      ..stop()
      ..reset();

    try {
      final String? path = await _recorder.stop();
      setState(() {
        _isRecording = false;
        _recordedPath = path;
      });
    } catch (e) {
      setState(() => _isRecording = false);
      if (!mounted) return;
      _snack('Kayıt durdurulamadı: $e', error: true);
    }
  }

  // ── Yeniden kaydet ────────────────────────────────────────────────────────
  void _retake() => setState(() {
        _recordedPath = null;
        _elapsedSeconds = 0;
      });

  // ── Analiz et → API ───────────────────────────────────────────────────────
  Future<void> _analyze() async {
    if (_recordedPath == null) return;
    setState(() => _isUploading = true);

    try {
      final bool ok = await _apiService.uploadAudio(
        File(_recordedPath!),
        _cat.label,
      );
      if (!mounted) return;

      if (ok) {
        _snack('Yapay zeka analiz etti! Görevler oluşturuldu ✓');
        await Future<void>.delayed(const Duration(milliseconds: 900));
        if (!mounted) return;
        Navigator.pop(context, true);
      } else {
        _snack('Yükleme başarısız. Backend çalışıyor mu?', error: true);
      }
    } catch (e) {
      if (!mounted) return;
      final String msg = e.toString();
      if (msg.contains('TimeoutException') || msg.contains('timed out')) {
        _snack('İşlem çok uzun sürdü (5dk+). Backend meşgul olabilir.', error: true);
      } else {
        _snack('Hata oluştu: $msg', error: true);
      }
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  // ── Snack yardımcısı ──────────────────────────────────────────────────────
  void _snack(String msg, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor:
            error ? const Color(0xFFEF4444) : const Color(0xFF16A34A),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14)),
        duration: const Duration(seconds: 3),
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
                msg,
                style: GoogleFonts.inter(
                    fontWeight: FontWeight.w600, color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: _buildAppBar(),
      body: SafeArea(
        child: Column(
          children: <Widget>[
            // ── Kategori şeridi ───────────────────────────────────────────
            const SizedBox(height: 24),
            _CategoryStrip(
              selected: _selectedCat,
              enabled: !_isRecording && !_hasStopped,
              onSelect: (int i) => setState(() => _selectedCat = i),
            ),

            // ── Orta alan: buton + kronometre ─────────────────────────────
            const Spacer(),
            _buildCenter(),
            const Spacer(),

            // ── Alt panel (stopped) ───────────────────────────────────────
            AnimatedSize(
              duration: const Duration(milliseconds: 380),
              curve: Curves.easeOutCubic,
              child: _hasStopped
                  ? _BottomPanel(
                      cat: _cat,
                      duration: _formattedTime,
                      isUploading: _isUploading,
                      onAnalyze: _analyze,
                      onRetake: _retake,
                    )
                  : const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }

  // ── AppBar ────────────────────────────────────────────────────────────────
  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: Colors.white,
      elevation: 0,
      surfaceTintColor: Colors.white,
      centerTitle: true,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios_new_rounded,
            color: Color(0xFF1E293B), size: 20),
        onPressed: () => Navigator.pop(context),
      ),
      title: Text(
        'Ses Kaydı',
        style: GoogleFonts.inter(
          fontSize: 17,
          fontWeight: FontWeight.w800,
          color: const Color(0xFF1E293B),
        ),
      ),
    );
  }

  // ── Orta içerik ───────────────────────────────────────────────────────────
  Widget _buildCenter() {
    final bool idle = !_isRecording && !_hasStopped;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        // Durum etiketi
        _StatusBadge(isRecording: _isRecording, hasStopped: _hasStopped),
        const SizedBox(height: 44),

        // Mikrofon butonu
        _MicButton(
          cat: _cat,
          isRecording: _isRecording,
          hasStopped: _hasStopped,
          pulseAnim: _pulseAnim,
          onTap: _isUploading
              ? null
              : () async {
                  if (_isRecording) {
                    await _stopRecording();
                  } else if (!_hasStopped) {
                    await _startRecording();
                  }
                },
        ),
        const SizedBox(height: 28),

        // Kronometre
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 280),
          child: (_isRecording || _hasStopped)
              ? Text(
                  _formattedTime,
                  key: const ValueKey<String>('timer'),
                  style: GoogleFonts.inter(
                    fontSize: 44,
                    fontWeight: FontWeight.w200,
                    letterSpacing: 6,
                    color: _isRecording
                        ? const Color(0xFFEF4444)
                        : const Color(0xFF94A3B8),
                  ),
                )
              : const SizedBox(
                  key: ValueKey<String>('empty'), height: 52),
        ),
        const SizedBox(height: 10),

        // Yardım / kayıt etiketi
        if (idle)
          Text(
            'Kaydetmek için dokunun',
            style: GoogleFonts.inter(
              fontSize: 13.5,
              color: const Color(0xFF94A3B8),
              fontWeight: FontWeight.w500,
            ),
          ),

        if (_isRecording)
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              _BlinkDot(),
              const SizedBox(width: 6),
              Text(
                'Kaydediliyor — durdurmak için dokun',
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFFEF4444),
                ),
              ),
            ],
          ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Yanıp sönen kırmızı nokta
// ═══════════════════════════════════════════════════════════════════════════════
class _BlinkDot extends StatefulWidget {
  @override
  State<_BlinkDot> createState() => _BlinkDotState();
}

class _BlinkDotState extends State<_BlinkDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
        opacity: _c,
        child: Container(
          width: 8,
          height: 8,
          decoration: const BoxDecoration(
            color: Color(0xFFEF4444),
            shape: BoxShape.circle,
          ),
        ),
      );
}

// ═══════════════════════════════════════════════════════════════════════════════
// Durum etiketi
// ═══════════════════════════════════════════════════════════════════════════════
class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.isRecording, required this.hasStopped});
  final bool isRecording;
  final bool hasStopped;

  @override
  Widget build(BuildContext context) {
    final String label;
    final Color color;
    final Color bg;
    final IconData icon;

    if (isRecording) {
      label = 'Kaydediliyor';
      color = const Color(0xFFEF4444);
      bg = const Color(0xFFFEF2F2);
      icon = Icons.graphic_eq_rounded;
    } else if (hasStopped) {
      label = 'Kayıt Tamamlandı';
      color = const Color(0xFF16A34A);
      bg = const Color(0xFFDCFCE7);
      icon = Icons.check_circle_outline_rounded;
    } else {
      label = 'Hazır';
      color = const Color(0xFF64748B);
      bg = const Color(0xFFF1F5F9);
      icon = Icons.mic_none_rounded;
    }

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      child: Container(
        key: ValueKey<String>(label),
        padding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, color: color, size: 13),
            const SizedBox(width: 5),
            Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Mikrofon butonu (pulse animasyonlu)
// ═══════════════════════════════════════════════════════════════════════════════
class _MicButton extends StatelessWidget {
  const _MicButton({
    required this.cat,
    required this.isRecording,
    required this.hasStopped,
    required this.pulseAnim,
    required this.onTap,
  });

  final _Cat cat;
  final bool isRecording;
  final bool hasStopped;
  final Animation<double> pulseAnim;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final Color btnColor = isRecording
        ? const Color(0xFFEF4444)
        : hasStopped
            ? const Color(0xFF16A34A)
            : cat.color;

    const double size = 130;

    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 190,
        height: 190,
        child: Stack(
          alignment: Alignment.center,
          children: <Widget>[
            // Pulse halkası — yalnızca kayıt sırasında
            if (isRecording)
              AnimatedBuilder(
                animation: pulseAnim,
                builder: (_, __) => Transform.scale(
                  scale: pulseAnim.value,
                  child: Container(
                    width: size,
                    height: size,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0xFFEF4444)
                          .withValues(alpha: 0.14),
                    ),
                  ),
                ),
              ),
            // Dış ince halka
            AnimatedContainer(
              duration: const Duration(milliseconds: 350),
              width: size + 30,
              height: size + 30,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: btnColor.withValues(alpha: 0.2),
                  width: 1.5,
                ),
              ),
            ),
            // Ana buton
            AnimatedContainer(
              duration: const Duration(milliseconds: 350),
              curve: Curves.easeOutCubic,
              width: size,
              height: size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: btnColor,
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: btnColor.withValues(alpha: 0.42),
                    blurRadius: isRecording ? 40 : 24,
                    spreadRadius: isRecording ? 6 : 0,
                    offset: const Offset(0, 12),
                  ),
                  BoxShadow(
                    color: btnColor.withValues(alpha: 0.15),
                    blurRadius: 60,
                    spreadRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                child: Icon(
                  isRecording
                      ? Icons.stop_rounded
                      : hasStopped
                          ? Icons.check_rounded
                          : Icons.mic_rounded,
                  key: ValueKey<bool>(isRecording),
                  color: Colors.white,
                  size: 52,
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
// Yatay kategori şeridi
// ═══════════════════════════════════════════════════════════════════════════════
class _CategoryStrip extends StatelessWidget {
  const _CategoryStrip({
    required this.selected,
    required this.enabled,
    required this.onSelect,
  });

  final int selected;
  final bool enabled;
  final void Function(int) onSelect;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 24),
        itemCount: _kCats.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (BuildContext ctx, int i) {
          final _Cat cat = _kCats[i];
          final bool active = selected == i;
          return GestureDetector(
            onTap: enabled ? () => onSelect(i) : null,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
              decoration: BoxDecoration(
                color: active ? cat.color : cat.bg,
                borderRadius: BorderRadius.circular(22),
                boxShadow: active
                    ? <BoxShadow>[
                        BoxShadow(
                          color: cat.color.withValues(alpha: 0.35),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ]
                    : null,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(cat.emoji,
                      style: TextStyle(
                          fontSize: 13,
                          color: enabled ? null : Colors.grey)),
                  const SizedBox(width: 5),
                  Text(
                    cat.label,
                    style: GoogleFonts.inter(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: active
                          ? Colors.white
                          : enabled
                              ? const Color(0xFF475569)
                              : const Color(0xFFCBD5E1),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Alt panel: gönder / yeniden kaydet
// ═══════════════════════════════════════════════════════════════════════════════
class _BottomPanel extends StatelessWidget {
  const _BottomPanel({
    required this.cat,
    required this.duration,
    required this.isUploading,
    required this.onAnalyze,
    required this.onRetake,
  });

  final _Cat cat;
  final String duration;
  final bool isUploading;
  final VoidCallback onAnalyze;
  final VoidCallback onRetake;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFFF8FAFC),
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Color(0x0E0F172A),
            blurRadius: 20,
            offset: Offset(0, -4),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 36),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          // Çizgi
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFFCBD5E1),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 18),

          // Kayıt özeti
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFF1F5F9)),
            ),
            child: Row(
              children: <Widget>[
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: const Color(0xFFDCFCE7),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Icon(Icons.audiotrack_rounded,
                      color: Color(0xFF16A34A), size: 18),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'Kayıt hazır',
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF1E293B),
                      ),
                    ),
                    Text(
                      '${cat.emoji}  ${cat.label}  •  $duration',
                      style: GoogleFonts.inter(
                        fontSize: 11.5,
                        color: const Color(0xFF64748B),
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                // Yeniden kaydet
                GestureDetector(
                  onTap: isUploading ? null : onRetake,
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.refresh_rounded,
                        color: Color(0xFF64748B), size: 18),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Ana buton
          SizedBox(
            width: double.infinity,
            height: 56,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: isUploading
                  ? Container(
                      key: const ValueKey<String>('loading'),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E293B),
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: <Widget>[
                          const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            'Yapay Zekaya Gönderiliyor…',
                            style: GoogleFonts.inter(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    )
                  : ElevatedButton.icon(
                      key: const ValueKey<String>('btn'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1E293B),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(18)),
                      ),
                      icon: const Icon(Icons.auto_awesome_rounded, size: 18),
                      label: Text(
                        'Yapay Zekaya Gönder (Analiz Et)',
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.2,
                        ),
                      ),
                      onPressed: onAnalyze,
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
