import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/api_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Model: Ses kaydı
// null transcript   → işlem bekliyor
// ""   transcript   → sessiz kayıt
// dolu transcript   → başarılı transkripsiyon
// ─────────────────────────────────────────────────────────────────────────────
class RecordItem {
  RecordItem({
    this.id,
    required this.fileName,
    required this.category,
    this.transcript,
    this.createdAt,
    this.autoTitle,
    this.notes,
    this.assistantNotes,
    this.originalFilename,
  });

  final int? id;
  final String fileName;
  final String category;
  final String? transcript;
  final DateTime? createdAt;
  final String? autoTitle;
  final String? notes;            // kullanıcının el ile yazdığı not
  final String? assistantNotes;   // asistanın çıkardığı madde madde not
  final String? originalFilename;

  RecordItem copyWith({String? notes, String? assistantNotes}) => RecordItem(
        id: id,
        fileName: fileName,
        category: category,
        transcript: transcript,
        createdAt: createdAt,
        autoTitle: autoTitle,
        notes: notes ?? this.notes,
        assistantNotes: assistantNotes ?? this.assistantNotes,
        originalFilename: originalFilename,
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Model: Görev
// ─────────────────────────────────────────────────────────────────────────────
class TaskItem {
  TaskItem({
    this.id,
    required this.title,
    this.dueDate,
    this.status = 'pending',
    this.recordId,
  });

  factory TaskItem.fromJson(Map<String, dynamic> json) => TaskItem(
        id: json['id'] as int?,
        title: (json['title'] as String?) ??
            (json['task_title'] as String?) ??
            'Görev',
        dueDate: json['due_date'] as String?,
        status: (json['status'] as String?) ?? 'pending',
        recordId: json['record_id'] as int?,
      );

  final int? id;
  final String title;
  final String? dueDate;
  final String status;
  final int? recordId;

  TaskItem copyWith({String? status}) => TaskItem(
        id: id,
        title: title,
        dueDate: dueDate,
        status: status ?? this.status,
        recordId: recordId,
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Model: Sohbet mesajı
// ─────────────────────────────────────────────────────────────────────────────
class ChatMessage {
  const ChatMessage({
    required this.text,
    required this.isUser,
    this.isTyping = false,
    this.options,
    this.isDocument = false,
    this.notesPayload,
  });

  final String text;
  final bool isUser;
  /// true ise bu mesaj gerçek bir metin değil, "yazıyor..." animasyonudur.
  final bool isTyping;
  /// Bot'un mesajının altında gösterilecek hızlı yanıt seçenekleri.
  final List<String>? options;
  /// true ise mesaj standart balon yerine belge/rapor kartı olarak gösterilir.
  final bool isDocument;
  /// Asistanın çıkardığı notlar — {recordId: int, text: String}
  /// null değilse mesajda "Notlara Kaydet" butonu gösterilir.
  final Map<String, dynamic>? notesPayload;
}

// ─────────────────────────────────────────────────────────────────────────────
// Merkezi Durum Yönetimi (ChangeNotifier)
// ─────────────────────────────────────────────────────────────────────────────
class AppState extends ChangeNotifier {
  final ApiService _api = ApiService();

  // ── Veri listeleri ────────────────────────────────────────────────────────
  final List<RecordItem> records = <RecordItem>[];
  final List<TaskItem> tasks = <TaskItem>[];

  // ── Yükleme bayrakları ────────────────────────────────────────────────────
  bool isInitialLoading = false;
  bool isUploadLoading = false;
  String currentFileName = '';
  String currentCategory = '';

  // ── Kullanıcı kimliği ─────────────────────────────────────────────────────
  String userName = 'Kullanici';
  String userEmail = 'kullanici@ornek.com';

  // ── Chatbot sohbet geçmişi ────────────────────────────────────────────────
  final List<ChatMessage> chatMessages = <ChatMessage>[
    const ChatMessage(
      text: 'VoiceToAction Asistanına hoş geldiniz! 👋\n\n'
          'Size nasıl yardımcı olabilirim?',
      isUser: false,
      options: <String>['CMD_TASKS', 'CMD_RECORDS'],
    ),
  ];

  bool isBotTyping = false;

  // ── Dark mode ─────────────────────────────────────────────────────────────
  bool isDarkMode = false;

  void toggleDarkMode() {
    isDarkMode = !isDarkMode;
    notifyListeners();
  }

  // ─── Kullanıcı kimliğini SharedPreferences'tan yükle ─────────────────────
  Future<void> loadUserIdentity() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String email =
        prefs.getString('user_email') ?? 'kullanici@ornek.com';
    final String name = prefs.getString('user_name') ?? 'Kullanici';
    userName = name.trim().isEmpty ? email : name;
    userEmail = email;
    notifyListeners();
  }

  // ─── API'den kayıt + görev listelerini çek ────────────────────────────────
  Future<void> fetchData() async {
    // Güvenlik çemberi: token yoksa API'yi çağırma
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? token = prefs.getString('access_token');
    if (token == null || token.isEmpty) {
      debugPrint('[AppState] fetchData ATLANDI: access_token yok.');
      return;
    }

    isInitialLoading = true;
    notifyListeners();

    final List<Map<String, dynamic>> rawRecords = await _api.getRecords();
    final List<Map<String, dynamic>> rawTasks = await _api.getTasks();

    records
      ..clear()
      ..addAll(rawRecords.map(_parseRecord));

    tasks
      ..clear()
      ..addAll(rawTasks.map(TaskItem.fromJson));

    isInitialLoading = false;
    notifyListeners();

    debugPrint('[AppState] fetchData tamamlandı: '
        '${records.length} kayıt, ${tasks.length} görev.');
  }

  // ─── Kayıt JSON → RecordItem dönüşümü ────────────────────────────────────
  RecordItem _parseRecord(Map<String, dynamic> r) {
    DateTime? createdAt;
    final String? raw = r['created_at'] as String?;
    if (raw != null && raw.isNotEmpty) {
      try {
        createdAt = DateTime.parse(raw);
      } catch (_) {}
    }

    final String? a = (r['transcribed_text'] as String?)?.trim();
    final String? b = (r['transcript'] as String?)?.trim();
    String? transcript;
    if (a == null && b == null) {
      transcript = null; // bekliyor
    } else {
      final String? preferred =
          (a != null && a.isNotEmpty) ? a : (b != null && b.isNotEmpty ? b : null);
      transcript = preferred ?? ''; // '' = sessiz kayıt
    }

    return RecordItem(
      id: r['id'] as int?,
      fileName: () {
        final String rawName = (r['file_name'] as String?) ?? 'Kayıt';
        final int dot = rawName.lastIndexOf('.');
        return dot > 0 ? rawName.substring(0, dot) : rawName;
      }(),
      category: (r['category'] as String?) ?? 'Diğer',
      transcript: transcript,
      createdAt: createdAt,
      autoTitle: (r['auto_title'] as String?)?.trim(),
      notes: r['notes'] as String?,
      assistantNotes: r['assistant_notes'] as String?,
      originalFilename: (r['original_filename'] as String?) ?? (r['file_name'] as String?),
    );
  }

  // ─── Upload yükleme durumunu güncelle ─────────────────────────────────────
  void setUploadState({
    required bool loading,
    String fileName = '',
    String category = '',
  }) {
    isUploadLoading = loading;
    currentFileName = fileName;
    currentCategory = category;
    notifyListeners();
  }

  // ─── Anlık kayıt ekle (upload sonrası) ───────────────────────────────────
  void insertRecord(RecordItem item) {
    records.insert(0, item);
    notifyListeners();
  }

  // ─── Kaydın kullanıcı notunu güncelle ────────────────────────────────────
  Future<bool> updateRecordNotes(int recordId, String notes) async {
    final bool ok = await _api.updateRecordNotes(recordId, notes);
    if (ok) {
      final int idx = records.indexWhere((RecordItem r) => r.id == recordId);
      if (idx != -1) {
        records[idx] = records[idx].copyWith(notes: notes);
        notifyListeners();
      }
    }
    return ok;
  }

  // ─── Kaydın asistan notunu güncelle ──────────────────────────────────────
  Future<bool> updateAssistantNotes(int recordId, String assistantNotes) async {
    final bool ok = await _api.updateAssistantNotes(recordId, assistantNotes);
    if (ok) {
      final int idx = records.indexWhere((RecordItem r) => r.id == recordId);
      if (idx != -1) {
        records[idx] = records[idx].copyWith(assistantNotes: assistantNotes);
        notifyListeners();
      }
    }
    return ok;
  }

  // ─── Anlık görev ekle (upload sonrası) ───────────────────────────────────
  void insertTask(TaskItem item) {
    tasks.insert(0, item);
    notifyListeners();
  }

  // ─── Kayıt sil → sunucudan doğrula → tüm listeyi yenile ────────────────────
  /// true → başarılı, false → API hatası (caller SnackBar gösterir).
  ///
  /// Optimistic güncelleme yerine sunucu-doğrulamalı yaklaşım:
  ///   1. API çağrısı yapılır.
  ///   2. Başarılıysa tüm kayıt listesi fetchData() ile sunucudan çekilir
  ///      → Yerel liste ile DB'nin senkronize olmama ihtimali sıfırlanır.
  ///   3. Başarısızsa ekrandaki liste değişmez; caller SnackBar gösterir.
  Future<bool> deleteRecord(int index) async {
    final RecordItem item = records[index];
    if (item.id == null) {
      records.removeAt(index);
      notifyListeners();
      return true;
    }

    final bool ok = await _api.deleteRecord(item.id!);
    if (ok) {
      // Sunucudan taze listeyi çek — yerel kopyayı değil, DB'yi kaynak al.
      await fetchData();
    }
    return ok;
  }

  // ─── Görev sil → sunucudan doğrula → tüm listeyi yenile ─────────────────
  Future<Map<String, dynamic>> deleteTask(int index) async {
    final TaskItem task = tasks[index];
    if (task.id == null) {
      tasks.removeAt(index);
      notifyListeners();
      return <String, dynamic>{'success': true};
    }

    final Map<String, dynamic> result = await _api.deleteTask(task.id!);
    if (result['success'] == true) {
      // Sunucudan taze listeyi çek — DB ile tam senkronizasyon.
      await fetchData();
    }
    return result;
  }

  // ─── Görev tikle (optimistic) ─────────────────────────────────────────────
  Future<Map<String, dynamic>> toggleTask(int index) async {
    final TaskItem task = tasks[index];
    if (task.id == null) return <String, dynamic>{'success': false};

    final String newStatus = task.status == 'done' ? 'pending' : 'done';
    tasks[index] = task.copyWith(status: newStatus);
    notifyListeners();

    final Map<String, dynamic> result = await _api.toggleTask(task.id!);
    if (result['success'] != true) {
      tasks[index] = task; // rollback
      notifyListeners();
    }
    return result;
  }

  // ─── Chatbot: mesaj gönder + yanıt al ────────────────────────────────────
  /// [text]               : API'ye gönderilen payload (CMD kodu veya düz metin).
  /// [displayText]        : Kullanıcı baloncuğunda gösterilecek etiket.
  /// [isDocumentResponse] : true ise bot yanıtı rapor kartı olarak gösterilir.
  Future<void> sendChatMessage(
    String text, {
    String? displayText,
    bool isDocumentResponse = false,
  }) async {
    final String trimmed = text.trim();
    if (trimmed.isEmpty || isBotTyping) return;

    // CMD_SELECT_30|Dosya Adı formatındaki mesajlarda API'ye sadece CMD kısmını gönder
    final List<String> parts = trimmed.split('|');
    final String apiMsg = parts[0];
    final String resolvedDisplay = (displayText?.trim().isNotEmpty == true)
        ? displayText!.trim()
        : (parts.length > 1 ? parts[1] : trimmed);
    final String bubbleText = resolvedDisplay;

    chatMessages.add(ChatMessage(text: bubbleText, isUser: true));
    chatMessages.add(const ChatMessage(text: '', isUser: false, isTyping: true));
    isBotTyping = true;
    notifyListeners();

    try {
      final Map<String, dynamic> result = await _api.sendMessageToBot(apiMsg);
      final String answer = (result['answer'] as String?) ?? 'Yanıt alınamadı.';
      final List<String> opts =
          (result['options'] as List<dynamic>?)?.cast<String>() ?? <String>[];

      // Asistanın not verisi varsa payload oluştur
      final String? notesText = result['notes_text'] as String?;
      final int? notesRecordId = result['record_id'] as int?;
      final Map<String, dynamic>? notesPayload =
          (notesText != null && notesRecordId != null)
              ? <String, dynamic>{'recordId': notesRecordId, 'text': notesText}
              : null;

      chatMessages.removeLast();
      chatMessages.add(ChatMessage(
        text: answer,
        isUser: false,
        options: opts.isEmpty ? null : opts,
        isDocument: isDocumentResponse,
        notesPayload: notesPayload,
      ));
    } catch (e) {
      chatMessages.removeLast();
      final String errText = e.toString().replaceFirst('Exception: ', '').trim();
      chatMessages.add(ChatMessage(
        text: errText.isNotEmpty ? errText : 'Bir hata oluştu.',
        isUser: false,
        options: <String>['CMD_TASKS', 'CMD_RECORDS'],
      ));
    } finally {
      isBotTyping = false;
      notifyListeners();
    }
  }

  // ─── Oturumu temizle (logout) ─────────────────────────────────────────────
  void clearSession() {
    records.clear();
    tasks.clear();
    chatMessages
      ..clear()
      ..add(
        const ChatMessage(
          text: 'VoiceToAction Asistanına hoş geldiniz! 👋\n\n'
              'Size nasıl yardımcı olabilirim?',
          isUser: false,
          options: <String>['CMD_TASKS', 'CMD_RECORDS'],
        ),
      );
    isBotTyping = false;
    userName = 'Kullanici';
    userEmail = 'kullanici@ornek.com';
    isInitialLoading = false;
    isUploadLoading = false;
    notifyListeners();
  }
}
