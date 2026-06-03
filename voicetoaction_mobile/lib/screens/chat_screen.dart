import 'dart:math' as math;

import 'package:flutter_markdown/flutter_markdown.dart';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';

typedef _Msg = ChatMessage;

// ─────────────────────────────────────────────────────────────────────────────
// CMD → İnsan okunabilir etiket + stil bilgisi
// ─────────────────────────────────────────────────────────────────────────────
class _CmdMeta {
  const _CmdMeta(this.label, this.colors);
  final String label;
  final List<Color> colors;
}

_CmdMeta _resolveMeta(String cmd) {
  const List<Color> blue = <Color>[Color(0xFF2563EB), Color(0xFF4F46E5)];
  const List<Color> violet = <Color>[Color(0xFF8B5CF6), Color(0xFF7C3AED)];
  const List<Color> amber = <Color>[Color(0xFFF59E0B), Color(0xFFEA580C)];
  const List<Color> green = <Color>[Color(0xFF16A34A), Color(0xFF059669)];
  const List<Color> cyan = <Color>[Color(0xFF0EA5E9), Color(0xFF2563EB)];
  const List<Color> slate = <Color>[Color(0xFF64748B), Color(0xFF475569)];
  const List<Color> orange = <Color>[Color(0xFFEA580C), Color(0xFFF97316)];
  const List<Color> sky = <Color>[Color(0xFF0284C7), Color(0xFF38BDF8)];
  const List<Color> indigo = <Color>[Color(0xFF4F46E5), Color(0xFF818CF8)];

  if (cmd == 'CMD_TASKS')   return const _CmdMeta('📋 Görevlerim', blue);
  if (cmd == 'CMD_RECORDS') return const _CmdMeta('🎙️ Kayıtlarım', blue);
  if (cmd == 'CMD_MENU')    return const _CmdMeta('🏠 Ana Menü', slate);

  if (RegExp(r'^CMD_SELECT_(\d+)$').hasMatch(cmd)) {
    final String id = RegExp(r'^CMD_SELECT_(\d+)$').firstMatch(cmd)?.group(1) ?? '';
    return _CmdMeta('🎙️ Kayıt #$id', blue);
  }

  if (RegExp(r'^CMD_SELECT_(\d+)\|(.+)$').hasMatch(cmd)) {
    final RegExpMatch? match = RegExp(r'^CMD_SELECT_(\d+)\|(.+)$').firstMatch(cmd);
    final String name = match?.group(2) ?? 'Kayıt Seç';
    return _CmdMeta('🎙️ $name', blue);
  }

  final RegExpMatch? summ = RegExp(r'^CMD_SUMMARIZE_(\d+)$').firstMatch(cmd);
  if (summ != null) return const _CmdMeta('📝 Özetle', violet);

  final RegExpMatch? ana  = RegExp(r'^CMD_ANALYZE_(\d+)$').firstMatch(cmd);
  if (ana  != null) return const _CmdMeta('🎯 Aksiyon Çıkar', amber);

  final RegExpMatch? cal  = RegExp(r'^CMD_CALENDAR_(\d+)$').firstMatch(cmd);
  if (cal  != null) return const _CmdMeta('📅 Takvim Planı Bul', cyan);

  final RegExpMatch? meet = RegExp(r'^CMD_MEETING_(\d+)$').firstMatch(cmd);
  if (meet != null) return const _CmdMeta('📌 Toplantı Notuna Çevir', green);

  final RegExpMatch? topics = RegExp(r'^CMD_TOPICS_(\d+)$').firstMatch(cmd);
  if (topics != null) return const _CmdMeta('📊 Konu Analizi', violet);

  final RegExpMatch? exam = RegExp(r'^CMD_EXAM_(\d+)$').firstMatch(cmd);
  if (exam != null) return const _CmdMeta('☕ Quiz Molası', violet);

  if (RegExp(r'^CMD_CODE_EXTRACT_(\d+)$').hasMatch(cmd))
    return const _CmdMeta('💻 Kod Çıkarıcı', cyan);

  if (RegExp(r'^CMD_CONCEPT_EXTRACT_(\d+)$').hasMatch(cmd))
    return const _CmdMeta('📚 Ders Notu & Kavramlar', green);

  if (RegExp(r'^CMD_SAVE_NOTE_(\d+)$').hasMatch(cmd))
    return const _CmdMeta('💾 Notlara Kaydet', orange);

  if (RegExp(r'^CMD_SIMPLIFY_(\d+)$').hasMatch(cmd))
    return const _CmdMeta('🧠 Mala Anlatır Gibi Anlat', sky);

  if (RegExp(r'^CMD_RESOURCES_(\d+)$').hasMatch(cmd))
    return const _CmdMeta('🎬 Kaynak Öner', amber);

  if (RegExp(r'^CMD_QANS_(\d+)_([A-D])_([A-D])$').hasMatch(cmd)) {
    final String choice = RegExp(r'^CMD_QANS_\d+_([A-D])_[A-D]$').firstMatch(cmd)?.group(1) ?? '';
    return _CmdMeta('$choice)', indigo);
  }

  if (RegExp(r'^CMD_TECH_EXTRACT_(\d+)$').hasMatch(cmd))
    return const _CmdMeta('💻 Teknik Analiz', cyan);

  if (RegExp(r'^CMD_TEAM_MATRIX_(\d+)$').hasMatch(cmd))
    return const _CmdMeta('👥 Ekip Matrisi', blue);

  // Pipe ile gelen display text varsa kullan
  if (cmd.contains('|')) {
    final List<String> parts = cmd.split('|');
    final String rawCmd = parts[0];
    final String displayText = parts[1];
    final _CmdMeta meta = _resolveMeta(rawCmd);
    if (meta.label != rawCmd) return meta;
    return _CmdMeta(displayText, slate);
  }

  // Hiçbiri eşleşmediyse ham CMD'yi temizle
  return _CmdMeta(
    cmd.split('|').last.replaceAll('CMD_', '').replaceAll('_', ' '),
    slate,
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Ana ekran
// ─────────────────────────────────────────────────────────────────────────────
class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});
  static const String routeName = '/chat';

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _textCtrl = TextEditingController();
  final ScrollController _scroll = ScrollController();
  int _lastMsgCount = 0;

  @override
  void dispose() {
    _textCtrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 340),
          curve: Curves.easeOutCubic,
        );
      }
    });
  }

  Future<void> _send() async {
    final String text = _textCtrl.text.trim();
    if (text.isEmpty || context.read<AppState>().isBotTyping) return;
    _textCtrl.clear();
    context.read<AppState>().sendChatMessage(text);
  }

  /// Buton tıklandığında: CMD kodu API'ye, insan etiketi baloncuğa.
  void _onOptionTap(String cmd) {
    final String rawCmd = cmd.split('|')[0].trim();
    final _CmdMeta meta = _resolveMeta(rawCmd);
    context.read<AppState>().sendChatMessage(
      rawCmd,
      displayText: meta.label,
    );
  }

  int _lastBotIndex(List<ChatMessage> msgs) {
    for (int i = msgs.length - 1; i >= 0; i--) {
      if (!msgs[i].isUser && !msgs[i].isTyping) return i;
    }
    return -1;
  }

  @override
  Widget build(BuildContext context) {
    final AppState state = context.watch<AppState>();
    final List<ChatMessage> msgs = state.chatMessages;

    if (msgs.length != _lastMsgCount) {
      _lastMsgCount = msgs.length;
      _scrollToBottom();
    }

    final int lastBot = _lastBotIndex(msgs);

    final bool isDarkMode = state.isDarkMode;

    return Scaffold(
      backgroundColor: isDarkMode ? const Color(0xFF0F172A) : const Color(0xFFF0F4F8),
      appBar: _ChatAppBar(),
      body: Column(
        children: <Widget>[
          Expanded(
            child: ListView.builder(
              controller: _scroll,
              padding: const EdgeInsets.fromLTRB(12, 16, 12, 8),
              itemCount: msgs.length,
              itemBuilder: (_, int i) => _BubbleRow(
                msg: msgs[i],
                isLastBot: i == lastBot,
                botTyping: state.isBotTyping,
                onOptionTap: _onOptionTap,
              ),
            ),
          ),
          _InputBar(
            controller: _textCtrl,
            isSending: state.isBotTyping,
            onSend: _send,
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// AppBar
// ─────────────────────────────────────────────────────────────────────────────
class _ChatAppBar extends StatelessWidget implements PreferredSizeWidget {
  @override
  Size get preferredSize => const Size.fromHeight(64);

  @override
  Widget build(BuildContext context) {
    final bool isDarkMode = context.watch<AppState>().isDarkMode;
    return Container(
      height: preferredSize.height + MediaQuery.of(context).padding.top,
      padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top),
      decoration: BoxDecoration(
        color: isDarkMode ? const Color(0xFF1E293B) : Colors.white,
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: <Widget>[
          _BackButton(onTap: () => Navigator.pop(context)),
          // Asistan avatarı
          ClipOval(
            child: Image.asset(
              'assets/voice_assistant.png',
              width: 50,
              height: 50,
              fit: BoxFit.cover,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'VoiceToAction Asistanı',
                  style: GoogleFonts.inter(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: isDarkMode ? const Color(0xFFF1F5F9) : const Color(0xFF1E293B),
                  ),
                ),
                Row(
                  children: <Widget>[
                    Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: const Color(0xFF22C55E),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      'Çevrimiçi',
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: isDarkMode ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),
        ],
      ),
    );
  }
}

class _BackButton extends StatelessWidget {
  const _BackButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        alignment: Alignment.center,
        child: const Icon(
          Icons.arrow_back_ios_new_rounded,
          color: Color(0xFF2563EB),
          size: 20,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Mesaj satırı
// ─────────────────────────────────────────────────────────────────────────────
class _BubbleRow extends StatelessWidget {
  const _BubbleRow({
    required this.msg,
    required this.isLastBot,
    required this.botTyping,
    required this.onOptionTap,
  });

  final _Msg msg;
  final bool isLastBot;
  final bool botTyping;
  final void Function(String) onOptionTap;

  @override
  Widget build(BuildContext context) {
    final bool showOptions = isLastBot &&
        !msg.isTyping &&
        (msg.options?.isNotEmpty ?? false);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        mainAxisAlignment:
            msg.isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: <Widget>[
          if (!msg.isUser) ...<Widget>[
            _AiAvatar(),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Column(
              crossAxisAlignment: msg.isUser
                  ? CrossAxisAlignment.end
                  : CrossAxisAlignment.start,
              children: <Widget>[
                if (msg.isTyping)
                  const _TypingBubble()
                else if (!msg.isUser && msg.isDocument)
                  _DocumentCard(
                    text: msg.text,
                    notesPayload: msg.notesPayload,
                  )
                else
                  _TextBubble(msg: msg),
                if (showOptions) ...<Widget>[
                  const SizedBox(height: 10),
                  _OptionsRow(
                    options: msg.options!,
                    active: !botTyping,
                    onTap: onOptionTap,
                  ),
                ],
              ],
            ),
          ),
          if (msg.isUser) const SizedBox(width: 8),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// AI avatar (küçük, kare)
// ─────────────────────────────────────────────────────────────────────────────
class _AiAvatar extends StatelessWidget {
  @override
  Widget build(BuildContext context) => ClipOval(
        child: Image.asset(
          'assets/voice_assistant.png',
          width: 36,
          height: 36,
          fit: BoxFit.cover,
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Markdown ayrıştırıcı yardımcıları (bot mesajları için)
// ─────────────────────────────────────────────────────────────────────────────

Widget _buildInlineText(String text, {bool isDarkMode = false}) {
  final Color textColor = isDarkMode ? const Color(0xFFF1F5F9) : const Color(0xFF1E293B);
  final List<String> parts = text.split('**');
  if (parts.length == 1) {
    return Text(
      text,
      style: GoogleFonts.inter(fontSize: 14, height: 1.6, color: textColor),
    );
  }
  final List<TextSpan> spans = <TextSpan>[];
  for (int i = 0; i < parts.length; i++) {
    spans.add(TextSpan(
      text: parts[i],
      style: TextStyle(
        fontWeight: i % 2 == 1 ? FontWeight.w700 : FontWeight.w400,
        color: textColor,
      ),
    ));
  }
  return RichText(
    text: TextSpan(
      style: GoogleFonts.inter(fontSize: 14, height: 1.6),
      children: spans,
    ),
  );
}

Widget _parseContent(String text, bool isUser, {bool isDarkMode = false}) {
  if (isUser) {
    return Text(
      text,
      style: GoogleFonts.inter(
        fontSize: 14.5,
        height: 1.6,
        color: Colors.white,
        fontWeight: FontWeight.w500,
      ),
    );
  }

  final Color textColor = isDarkMode ? const Color(0xFFF1F5F9) : const Color(0xFF1E293B);
  final Color emojiBg = isDarkMode ? const Color(0xFF334155) : const Color(0xFFF1F5F9);
  final Color emojiBorder = isDarkMode ? const Color(0xFF334155) : const Color(0xFFE2E8F0);

  final List<String> lines = text.split('\n');
  final List<Widget> widgets = <Widget>[];

  for (final String line in lines) {
    final String trimmed = line.trim();
    if (trimmed.isEmpty) {
      widgets.add(const SizedBox(height: 4));
      continue;
    }

    // Başlık: sadece **text** olan satır
    if (trimmed.startsWith('**') && trimmed.endsWith('**')) {
      widgets.add(Text(
        trimmed.replaceAll('**', ''),
        style: GoogleFonts.inter(
          fontSize: 14,
          fontWeight: FontWeight.w800,
          color: textColor,
        ),
      ));
      continue;
    }

    // Emoji header satırları
    if (RegExp(r'^[📊📋📅🎓📄🔑⚡📌📁🎯💪😰😊😕🔥😐]').hasMatch(trimmed)) {
      widgets.add(Container(
        margin: const EdgeInsets.symmetric(vertical: 2),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: emojiBg,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: emojiBorder),
        ),
        child: _buildInlineText(trimmed, isDarkMode: isDarkMode),
      ));
      continue;
    }

    // Bullet: • veya - ile başlayan
    if (trimmed.startsWith('•') || trimmed.startsWith('-')) {
      widgets.add(Padding(
        padding: const EdgeInsets.only(left: 8, top: 2, bottom: 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text(
              '•  ',
              style: TextStyle(
                color: Color(0xFF6366F1),
                fontWeight: FontWeight.w700,
              ),
            ),
            Expanded(
              child: _buildInlineText(
                trimmed.replaceFirst(RegExp(r'^[•\-]\s*'), ''),
                isDarkMode: isDarkMode,
              ),
            ),
          ],
        ),
      ));
      continue;
    }

    widgets.add(_buildInlineText(trimmed, isDarkMode: isDarkMode));
  }

  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: widgets,
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Metin baloncuğu
// ─────────────────────────────────────────────────────────────────────────────
class _TextBubble extends StatelessWidget {
  const _TextBubble({required this.msg});
  final _Msg msg;

  @override
  Widget build(BuildContext context) {
    final bool isUser = msg.isUser;
    final bool isDarkMode = context.watch<AppState>().isDarkMode;
    final Color botBg = isDarkMode ? const Color(0xFF1E293B) : Colors.white;

    return Container(
      constraints: BoxConstraints(
        maxWidth: MediaQuery.of(context).size.width * (isUser ? 0.85 : 0.88),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        gradient: isUser
            ? const LinearGradient(
                colors: <Color>[Color(0xFF3B82F6), Color(0xFF1D4ED8)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              )
            : null,
        color: isUser ? null : botBg,
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(18),
          topRight: const Radius.circular(18),
          bottomLeft: Radius.circular(isUser ? 18 : 4),
          bottomRight: Radius.circular(isUser ? 4 : 18),
        ),
        border: isUser
            ? null
            : const Border(
                left: BorderSide(color: Color(0xFF6366F1), width: 3),
              ),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: isUser
          ? _parseContent(msg.text, isUser, isDarkMode: isDarkMode)
          : MarkdownBody(
              data: msg.text,
              styleSheet: MarkdownStyleSheet(
                p: TextStyle(
                  color: isDarkMode
                      ? const Color(0xFFF1F5F9)
                      : const Color(0xFF1E293B),
                  fontSize: 14,
                  height: 1.5,
                ),
                strong: const TextStyle(fontWeight: FontWeight.w700),
                code: TextStyle(
                  backgroundColor: const Color(0xFF334155),
                  color: const Color(0xFF93C5FD),
                  fontSize: 12,
                  fontFamily: 'monospace',
                ),
                codeblockDecoration: BoxDecoration(
                  color: const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFF334155)),
                ),
                listBullet: TextStyle(
                  color: isDarkMode
                      ? const Color(0xFF94A3B8)
                      : const Color(0xFF64748B),
                ),
                h1: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: Colors.white),
                h2: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Colors.white),
                h3: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.white),
              ),
              shrinkWrap: true,
            ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Seçenek butonları — yatay kaydırılabilir
// ─────────────────────────────────────────────────────────────────────────────
class _OptionsRow extends StatelessWidget {
  const _OptionsRow({
    required this.options,
    required this.active,
    required this.onTap,
  });

  final List<String> options;
  final bool active;
  final void Function(String) onTap;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: options.asMap().entries.map((MapEntry<int, String> e) {
          return Padding(
            padding: EdgeInsets.only(right: e.key < options.length - 1 ? 8 : 0),
            child: _OptionChip(
              cmd: e.value,
              active: active,
              onTap: active ? () => onTap(e.value) : null,
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _OptionChip extends StatelessWidget {
  const _OptionChip({
    required this.cmd,
    required this.active,
    this.onTap,
  });

  final String cmd;
  final bool active;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final _CmdMeta meta = _resolveMeta(cmd);
    final List<Color> colors = active
        ? meta.colors
        : const <Color>[Color(0xFFCBD5E1), Color(0xFFCBD5E1)];

    return GestureDetector(
      onTap: onTap,
      child: AnimatedOpacity(
        opacity: active ? 1.0 : 0.45,
        duration: const Duration(milliseconds: 200),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: colors,
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(22),
            boxShadow: active
                ? <BoxShadow>[
                    BoxShadow(
                      color: colors.first.withValues(alpha: 0.5),
                      blurRadius: 15,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : null,
          ),
          child: Text(
            meta.label,
            style: GoogleFonts.inter(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Colors.white,
              letterSpacing: 0.1,
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Belge / Rapor Kartı  (Toplantı Notları için)
// ─────────────────────────────────────────────────────────────────────────────
class _DocumentCard extends StatefulWidget {
  const _DocumentCard({required this.text, this.notesPayload});
  final String text;
  final Map<String, dynamic>? notesPayload;

  @override
  State<_DocumentCard> createState() => _DocumentCardState();
}

class _DocumentCardState extends State<_DocumentCard> {
  bool _saving = false;
  bool _saved = false;

  Future<void> _saveNotes() async {
    final Map<String, dynamic>? payload = widget.notesPayload;
    if (payload == null) return;
    final int recordId = payload['recordId'] as int;
    final String notesText = payload['text'] as String;

    setState(() => _saving = true);
    final bool ok =
        await context.read<AppState>().updateAssistantNotes(recordId, notesText);
    if (mounted) {
      setState(() {
        _saving = false;
        _saved = ok;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(ok ? '✅ Notlar kaydedildi!' : 'Kaydedilemedi, tekrar dene.'),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final double maxW = MediaQuery.of(context).size.width * 0.84;
    return Container(
      constraints: BoxConstraints(maxWidth: maxW),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.07),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // ── Başlık çubuğu ──────────────────────────────────────────────
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: <Color>[Color(0xFF16A34A), Color(0xFF059669)],
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
              ),
              borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
            child: Row(
              children: <Widget>[
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.description_rounded,
                    color: Colors.white,
                    size: 16,
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  'Ders & Toplantı Notu',
                  style: GoogleFonts.inter(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    letterSpacing: 0.2,
                  ),
                ),
              ],
            ),
          ),
          // ── İçerik ─────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
            child: Text(
              widget.text,
              style: GoogleFonts.inter(
                fontSize: 14,
                height: 1.65,
                color: const Color(0xFF1E293B),
              ),
            ),
          ),
          // ── Notlara Kaydet butonu ───────────────────────────────────────
          if (widget.notesPayload != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
              child: SizedBox(
                width: double.infinity,
                height: 40,
                child: ElevatedButton.icon(
                  onPressed: (_saving || _saved) ? null : _saveNotes,
                  icon: _saving
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : Icon(
                          _saved
                              ? Icons.check_circle_rounded
                              : Icons.bookmark_add_rounded,
                          size: 16,
                        ),
                  label: Text(
                    _saving
                        ? 'Kaydediliyor…'
                        : (_saved ? 'Notlara Kaydedildi' : 'Notlara Kaydet'),
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _saved
                        ? const Color(0xFF2563EB)
                        : const Color(0xFF16A34A),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    elevation: 0,
                  ),
                ),
              ),
            ),
          // ── Alt çizgi ──────────────────────────────────────────────────
          Container(
            height: 3,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: <Color>[Color(0xFF16A34A), Color(0xFF059669)],
              ),
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(16)),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Yazıyor... baloncuğu
// ─────────────────────────────────────────────────────────────────────────────
class _TypingBubble extends StatefulWidget {
  const _TypingBubble();

  @override
  State<_TypingBubble> createState() => _TypingBubbleState();
}

class _TypingBubbleState extends State<_TypingBubble>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool isDarkMode = context.watch<AppState>().isDarkMode;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(
        color: isDarkMode ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(18),
          topRight: Radius.circular(18),
          bottomLeft: Radius.circular(4),
          bottomRight: Radius.circular(18),
        ),
        border: const Border(
          left: BorderSide(color: Color(0xFF6366F1), width: 3),
        ),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: List<Widget>.generate(3, (int i) {
          return AnimatedBuilder(
            animation: _ctrl,
            builder: (_, _) {
              final double s = 0.6 +
                  0.4 *
                      ((math.sin((_ctrl.value * math.pi * 2) -
                                  (i * math.pi / 2)) +
                              1) /
                          2);
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: Transform.scale(
                  scale: s,
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: const Color(0xFF6366F1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
              );
            },
          );
        }),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Metin giriş çubuğu
// ─────────────────────────────────────────────────────────────────────────────
class _InputBar extends StatelessWidget {
  const _InputBar({
    required this.controller,
    required this.isSending,
    required this.onSend,
  });

  final TextEditingController controller;
  final bool isSending;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final bool isDarkMode = context.watch<AppState>().isDarkMode;
    return Container(
      padding: EdgeInsets.fromLTRB(
          14, 10, 14, 10 + MediaQuery.of(context).padding.bottom),
      decoration: BoxDecoration(
        color: isDarkMode ? const Color(0xFF1E293B) : Colors.white,
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, -3),
          ),
        ],
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: isDarkMode ? const Color(0xFF334155) : const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(26),
              ),
              child: TextField(
                controller: controller,
                minLines: 1,
                maxLines: 5,
                textInputAction: TextInputAction.newline,
                style: GoogleFonts.inter(
                  fontSize: 14.5,
                  color: isDarkMode ? const Color(0xFFF1F5F9) : const Color(0xFF1E293B),
                ),
                decoration: InputDecoration(
                  hintText: 'Bir şey sor veya butona bas…',
                  hintStyle: GoogleFonts.inter(
                    fontSize: 14,
                    color: isDarkMode ? const Color(0xFF94A3B8) : const Color(0xFF94A3B8),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 18, vertical: 11),
                  border: InputBorder.none,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          GestureDetector(
            onTap: isSending ? null : onSend,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                gradient: isSending
                    ? const LinearGradient(
                        colors: <Color>[Color(0xFFCBD5E1), Color(0xFFCBD5E1)],
                      )
                    : const LinearGradient(
                        colors: <Color>[Color(0xFF2563EB), Color(0xFF1D4ED8)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                borderRadius: BorderRadius.circular(23),
                boxShadow: isSending
                    ? null
                    : <BoxShadow>[
                        BoxShadow(
                          color: const Color(0xFF2563EB).withValues(alpha: 0.35),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
              ),
              child: isSending
                  ? const Center(
                      child: SizedBox(
                        width: 19,
                        height: 19,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.3,
                          color: Colors.white,
                        ),
                      ),
                    )
                  : const Icon(Icons.send_rounded,
                      color: Colors.white, size: 19),
            ),
          ),
        ],
      ),
    );
  }
}
