import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart' show NavigatorState;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../app_navigator.dart';
import '../screens/login_screen.dart';

class ApiService {
  static const String baseUrl = 'http://10.196.143.100:8000/api';

  String audioUrl(int recordId) => '$baseUrl/records/$recordId/audio';

  // ── 401 merkezi işleyici ────────────────────────────────────────────────────
  // Token geçersiz → yerel oturumu temizle + LoginScreen'e yönlendir.
  static Future<void> _handle401() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.clear();

    final NavigatorState? nav = appNavigatorKey.currentState;
    if (nav == null) return;

    // Tüm yığını temizleyip LoginScreen'e gönder
    nav.pushNamedAndRemoveUntil(
      LoginScreen.routeName,
      (_) => false,
    );
  }

  /// Başarıda void döner; hata durumunda [Exception] fırlatır.
  /// Token, bu metod tamamlanmadan KESİNLİKLE SharedPreferences'a yazılmaz.
  Future<void> login(String email, String password) async {
    final Uri url = Uri.parse('$baseUrl/login');

    final http.Response response = await http.post(
      url,
      headers: <String, String>{
        'Content-Type': 'application/x-www-form-urlencoded',
        'accept': 'application/json',
      },
      body: <String, String>{
        'username': email,
        'password': password,
      },
    );

    if (response.statusCode != 200) {
      final String message = _extractDetailMessage(response.body);
      print(
        '[ApiService] login hata. Status: ${response.statusCode}, '
        'Detail: $message',
      );
      throw Exception(message);
    }

    final Map<String, dynamic> data =
        jsonDecode(response.body) as Map<String, dynamic>;
    final String? accessToken = data['access_token'] as String?;

    if (accessToken == null || accessToken.isEmpty) {
      print('[ApiService] login hata: access_token yok. Body: ${response.body}');
      throw Exception('Sunucudan geçerli bir token alınamadı.');
    }

    // Token ve kullanıcı bilgileri tam olarak kaydedilmeden metod bitmez.
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString('access_token', accessToken);
    await prefs.setString('user_email', email);
    final String? fullName = data['full_name'] as String?;
    if (fullName != null && fullName.trim().isNotEmpty) {
      await prefs.setString('user_name', fullName.trim());
    }
    final int? userId = data['user_id'] as int?;
    if (userId != null) {
      await prefs.setInt('user_id', userId);
    }
    print('[ApiService] login başarılı. Token kaydedildi, user_id=$userId');
  }

  Future<Map<String, dynamic>> register(
    String email,
    String password,
    String fullName,
  ) async {
    final Uri url = Uri.parse('$baseUrl/register');

    try {
      final http.Response response = await http.post(
        url,
        headers: <String, String>{
          'Content-Type': 'application/json',
        },
        body: jsonEncode(<String, String>{
          'full_name': fullName,
          'email': email,
          'password': password,
        }),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        return <String, dynamic>{'success': true};
      }

      if (response.statusCode == 400) {
        final String message = _extractDetailMessage(response.body);
        print('Register failed. Status: 400, Detail: $message');
        return <String, dynamic>{
          'success': false,
          'message': message,
        };
      }

      print(
        'Register failed. Status: ${response.statusCode}, Body: ${response.body}',
      );
      return <String, dynamic>{
        'success': false,
        'message': 'Kayit basarisiz (${response.statusCode})',
      };
    } catch (e) {
      print('Register request error: $e');
      return <String, dynamic>{
        'success': false,
        'message': 'Register request error: $e',
      };
    }
  }

  Future<Map<String, dynamic>> updateProfile(String newName) async {
    final String trimmedName = newName.trim();
    if (trimmedName.isEmpty) {
      return <String, dynamic>{
        'success': false,
        'message': 'Isim alani bos olamaz.',
      };
    }

    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? token = prefs.getString('access_token');
    final String? email = prefs.getString('user_email');

    await prefs.setString('user_name', trimmedName);

    if (token == null || token.isEmpty) {
      return <String, dynamic>{
        'success': true,
        'message': 'Isim yerel olarak guncellendi.',
      };
    }

    final Uri url = Uri.parse('$baseUrl/update-profile');

    try {
      final http.Response response = await http.put(
        url.replace(queryParameters: <String, String>{
          'newName': trimmedName,
          'email': email ?? '',
        }),
        headers: <String, String>{
          'Content-Type': 'application/json',
          'accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode(<String, String>{}),
      );

      if (response.statusCode == 200) {
        return <String, dynamic>{'success': true};
      }

      print(
        'Update profile failed. Status: ${response.statusCode}, Body: ${response.body}',
      );
      return <String, dynamic>{
        'success': true,
        'message': 'Isim yerel olarak guncellendi.',
      };
    } catch (e) {
      print('Update profile request error: $e');
      return <String, dynamic>{
        'success': true,
        'message': 'Isim yerel olarak guncellendi.',
      };
    }
  }

  String _extractDetailMessage(String responseBody) {
    try {
      final dynamic decoded = jsonDecode(responseBody);
      if (decoded is Map<String, dynamic>) {
        final dynamic detail = decoded['detail'];
        if (detail is String && detail.trim().isNotEmpty) {
          return detail;
        }
      }
    } catch (_) {}

    return 'Islem basarisiz.';
  }

  /// POST /api/transcribe — kayıt dosyasını backend'e gönderir.
  /// Her durumda (başarı / hata / timeout) bool döner; asla Exception fırlatmaz.
  /// Çağıran widget'ın finally bloğu isLoading = false yapabilir.
  Future<bool> uploadAudio(File file, String category) async {
    final Uri url = Uri.parse('$baseUrl/transcribe');

    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? token = prefs.getString('access_token');

    if (token == null || token.isEmpty) {
      print('[ApiService] uploadAudio HATA: token bulunamadı.');
      return false;
    }

    // Uzun ses kayıtları için 300 s — hem bağlantı hem yanıt gövdesi için.
    const Duration _kTimeout = Duration(seconds: 300);

    try {
      final http.MultipartRequest request =
          http.MultipartRequest('POST', url)
            ..headers['Authorization'] = 'Bearer $token'
            ..fields['category'] = category
            ..files
                .add(await http.MultipartFile.fromPath('file', file.path));

      final http.StreamedResponse streamed =
          await request.send().timeout(_kTimeout);

      // bytesToString'e de ayrıca timeout ekle; sunucu yanıtı yavaş
      // gönderirse burada da kilitlenilebilir.
      final String body =
          await streamed.stream.bytesToString().timeout(_kTimeout);

      print('[ApiService] uploadAudio → ${streamed.statusCode}');
      if (streamed.statusCode == 401) {
        await _handle401();
        return false;
      }
      if (streamed.statusCode == 200) {
        try {
          final Map<String, dynamic> data =
              jsonDecode(body) as Map<String, dynamic>;
          final String? errMsg = data['error'] as String?;
          if (errMsg != null && errMsg.isNotEmpty) {
            print('[ApiService] uploadAudio uyarı: $errMsg');
          }
        } catch (_) {}
        return true;
      }
      print('[ApiService] uploadAudio HATA ${streamed.statusCode}: $body');
      return false;
    } on Exception catch (e) {
      final String msg = e.toString();
      if (msg.contains('TimeoutException') || msg.contains('timed out')) {
        print('[ApiService] uploadAudio ZAMAN AŞIMI (300s): $e');
      } else {
        print('[ApiService] uploadAudio hata: $e');
      }
      // Exception fırlatmak yerine false döndür →
      // çağıran _analyze() finally bloğu isLoading = false yapar.
      return false;
    }
  }

  /// Returns `{'text': String, 'tasks': List<dynamic>}` on success.
  /// Throws [Exception] on timeout, network error, or server error
  /// so the caller can always set isLoading=false in its catch/finally
  /// and show a Snackbar to the user.
  Future<Map<String, dynamic>?> uploadMediaAndTranscribe(
    File file, {
    String category = 'Diğer',
  }) async {
    final Uri url = Uri.parse('$baseUrl/transcribe');

    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? token = prefs.getString('access_token');

    print('[ApiService] uploadMediaAndTranscribe → URL: $url');
    print('[ApiService] kategori=$category  dosya=${file.path}');

    // JWT token zorunlu — eksikse işlemi durdur
    if (token == null || token.isEmpty) {
      print('[ApiService] HATA: access_token bulunamadı. Kullanıcı giriş yapmamış.');
      throw Exception('Oturum bulunamadı. Lütfen tekrar giriş yapın.');
    }

    try {
      // user_id artık Form alanı değil; kimlik JWT Bearer token üzerinden doğrulanıyor.
      final http.MultipartRequest request = http.MultipartRequest('POST', url)
        ..headers['Authorization'] = 'Bearer $token'
        ..fields['category'] = category
        ..files.add(await http.MultipartFile.fromPath('file', file.path));

      print('[ApiService] Gönderilen form alanları: ${request.fields}');

      // 300 saniyelik (5 dk) toplam süre — hem bağlantı hem yanıt gövdesi için.
      const Duration _kTimeout = Duration(seconds: 300);

      final http.StreamedResponse streamedResponse =
          await request.send().timeout(_kTimeout);

      // Yanıt gövdesi okunurken de sunucu takılabilir; ayrıca timeout ekle.
      final String responseBody = await streamedResponse.stream
          .bytesToString()
          .timeout(_kTimeout);

      print('[ApiService] Transcribe yanıt kodu: '
          '${streamedResponse.statusCode}');
      print('[ApiService] Transcribe yanıt body: '
          '${responseBody.length > 300 ? responseBody.substring(0, 300) : responseBody}');

      if (streamedResponse.statusCode == 401) {
        await _handle401();
        throw Exception('Oturum süresi doldu. Lütfen tekrar giriş yapın.');
      }

      if (streamedResponse.statusCode == 200) {
        final Map<String, dynamic> data =
            jsonDecode(responseBody) as Map<String, dynamic>;
        return <String, dynamic>{
          'text': (data['text'] as String?) ?? '',
          'tasks': (data['tasks'] as List<dynamic>?) ?? <dynamic>[],
          'record_id': data['record_id'],
          'error': data['error'], // null veya hata mesajı
        };
      }

      print('[ApiService] HATA ${streamedResponse.statusCode}: $responseBody');
      throw Exception(
        'Sunucu hatası (${streamedResponse.statusCode}). Lütfen tekrar deneyin.',
      );
    } on Exception catch (e, stack) {
      final String msg = e.toString();
      if (msg.contains('TimeoutException') || msg.contains('timed out')) {
        print('[ApiService] Transcribe ZAMAN AŞIMI (300s): $e');
        throw Exception(
          'İşlem zaman aşımına uğradı (5 dk). '
          'Daha kısa bir kayıt deneyin veya bağlantınızı kontrol edin.',
        );
      }
      print('[ApiService] Transcribe istek hatası: $e');
      print('[ApiService] Stack trace: $stack');
      rethrow;
    }
  }

  /// GET /api/records — JWT token sahibinin kayıtları.
  /// URL'de user_id YOK; kimlik doğrulama sadece Bearer token ile yapılır.
  Future<List<Map<String, dynamic>>> getRecords() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? token = prefs.getString('access_token');

    if (token == null || token.isEmpty) {
      print('[ApiService] getRecords ATLANDI: token yok.');
      return <Map<String, dynamic>>[];
    }

    // Artık user_id URL'de yok — 403 uyuşmazlığı imkânsız.
    final Uri url = Uri.parse('$baseUrl/records');
    print('[ApiService] getRecords URL: $url');

    try {
      final http.Response response = await http.get(
        url,
        headers: <String, String>{
          'accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      print('[ApiService] getRecords yanıt kodu: ${response.statusCode}');

      if (response.statusCode == 401 || response.statusCode == 403) {
        // Token geçersiz veya oturum bozuk → temizle ve login'e yönlendir.
        print('[ApiService] getRecords ${response.statusCode}: oturum sıfırlanıyor.');
        await _handle401();
        return <Map<String, dynamic>>[];
      }

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body) as List<dynamic>;
        print('[ApiService] getRecords: ${data.length} kayıt döndü.');
        return data.whereType<Map<String, dynamic>>().toList();
      }

      print('[ApiService] getRecords HATA ${response.statusCode}: ${response.body}');
      return <Map<String, dynamic>>[];
    } catch (e, stack) {
      print('[ApiService] getRecords istek hatası: $e\n$stack');
      return <Map<String, dynamic>>[];
    }
  }

  /// GET /api/tasks — JWT token sahibinin görevleri.
  /// URL'de user_id YOK; kimlik doğrulama sadece Bearer token ile yapılır.
  Future<List<Map<String, dynamic>>> getTasks() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? token = prefs.getString('access_token');

    if (token == null || token.isEmpty) {
      print('[ApiService] getTasks ATLANDI: token yok.');
      return <Map<String, dynamic>>[];
    }

    // Artık user_id URL'de yok — 403 uyuşmazlığı imkânsız.
    final Uri url = Uri.parse('$baseUrl/tasks');
    print('[ApiService] getTasks URL: $url');

    try {
      final http.Response response = await http.get(
        url,
        headers: <String, String>{
          'accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      print('[ApiService] getTasks yanıt kodu: ${response.statusCode}');

      if (response.statusCode == 401 || response.statusCode == 403) {
        // Token geçersiz veya oturum bozuk → temizle ve login'e yönlendir.
        print('[ApiService] getTasks ${response.statusCode}: oturum sıfırlanıyor.');
        await _handle401();
        return <Map<String, dynamic>>[];
      }

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body) as List<dynamic>;
        print('[ApiService] getTasks: ${data.length} görev döndü.');
        return data.whereType<Map<String, dynamic>>().toList();
      }

      print('[ApiService] getTasks HATA ${response.statusCode}: ${response.body}');
      return <Map<String, dynamic>>[];
    } catch (e, stack) {
      print('[ApiService] getTasks istek hatası: $e\n$stack');
      return <Map<String, dynamic>>[];
    }
  }

  /// DELETE /api/tasks/{taskId} — görevi kalıcı olarak siler.
  /// Başarıda {'success': true} döner.
  Future<Map<String, dynamic>> deleteTask(int taskId) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? token = prefs.getString('access_token');
    final Uri url = Uri.parse('$baseUrl/tasks/$taskId');

    if (token == null || token.isEmpty) {
      return <String, dynamic>{
        'success': false,
        'message': 'Oturum bulunamadı.',
      };
    }

    try {
      final http.Response response = await http.delete(
        url,
        headers: <String, String>{
          'accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 401) {
        await _handle401();
        return <String, dynamic>{'success': false, 'message': 'Oturum süresi doldu.'};
      }

      if (response.statusCode == 200) {
        print('[ApiService] deleteTask #$taskId: silindi.');
        return <String, dynamic>{'success': true};
      }

      print('[ApiService] deleteTask HATA ${response.statusCode}: ${response.body}');
      return <String, dynamic>{
        'success': false,
        'message': _extractDetailMessage(response.body),
      };
    } catch (e) {
      print('[ApiService] deleteTask istek hatası: $e');
      return <String, dynamic>{
        'success': false,
        'message': 'İstek hatası: $e',
      };
    }
  }

  /// DELETE /api/records/{recordId} — ses kaydını ve bağlı görevleri kalıcı siler.
  Future<bool> deleteRecord(int recordId) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? token = prefs.getString('access_token');

    if (token == null || token.isEmpty) {
      print('[ApiService] deleteRecord HATA: token yok.');
      return false;
    }

    try {
      final http.Response response = await http.delete(
        Uri.parse('$baseUrl/records/$recordId'),
        headers: <String, String>{
          'accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );
      print('[ApiService] deleteRecord #$recordId → ${response.statusCode}');
      if (response.statusCode == 401) {
        await _handle401();
        return false;
      }
      return response.statusCode == 200;
    } catch (e) {
      print('[ApiService] deleteRecord hata: $e');
      return false;
    }
  }

  /// PATCH /api/records/{recordId} — kaydın notlarını günceller.
  Future<bool> updateRecordNotes(int recordId, String notes) async {
    return _patchRecord(recordId, <String, String>{
      'notes': notes,
    });
  }

  /// PATCH /api/records/{recordId} — asistanın çıkardığı notları kaydeder.
  Future<bool> updateAssistantNotes(int recordId, String assistantNotes) async {
    return _patchRecord(recordId, <String, String>{
      'assistant_notes': assistantNotes,
    });
  }

  Future<bool> _patchRecord(int recordId, Map<String, String> fields) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? token = prefs.getString('access_token');
    if (token == null || token.isEmpty) return false;

    try {
      final String body = fields.entries
          .map((MapEntry<String, String> e) =>
              '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}')
          .join('&');

      final http.Response response = await http.patch(
        Uri.parse('$baseUrl/records/$recordId'),
        headers: <String, String>{
          'accept': 'application/json',
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/x-www-form-urlencoded',
        },
        body: body,
      );
      print('[ApiService] patchRecord #$recordId → ${response.statusCode}');
      if (response.statusCode == 401) {
        await _handle401();
        return false;
      }
      return response.statusCode == 200;
    } catch (e) {
      print('[ApiService] patchRecord hata: $e');
      return false;
    }
  }

  /// PUT /api/tasks/{taskId}/toggle — is_completed değerini tersine çevirir.
  /// Başarıda {'success': true, 'status': 'done'|'pending', 'is_completed': bool} döner.
  Future<Map<String, dynamic>> toggleTask(int taskId) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? token = prefs.getString('access_token');
    final Uri url = Uri.parse('$baseUrl/tasks/$taskId/toggle');

    if (token == null || token.isEmpty) {
      return <String, dynamic>{
        'success': false,
        'message': 'Oturum bulunamadı.',
      };
    }

    try {
      final http.Response response = await http.put(
        url,
        headers: <String, String>{
          'accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 401) {
        await _handle401();
        return <String, dynamic>{'success': false, 'message': 'Oturum süresi doldu.'};
      }

      if (response.statusCode == 200) {
        final Map<String, dynamic> data =
            jsonDecode(response.body) as Map<String, dynamic>;
        return <String, dynamic>{
          'success': true,
          'status': data['status'] as String? ?? 'pending',
          'is_completed': data['is_completed'] as bool? ?? false,
          'message': data['message'] as String? ?? '',
        };
      }

      print('[ApiService] toggleTask HATA ${response.statusCode}: ${response.body}');
      return <String, dynamic>{
        'success': false,
        'message': _extractDetailMessage(response.body),
      };
    } catch (e) {
      print('[ApiService] toggleTask istek hatası: $e');
      return <String, dynamic>{
        'success': false,
        'message': 'İstek hatası: $e',
      };
    }
  }

  /// POST /api/chat — Deterministik asistan (State Machine).
  /// Başarıda {"answer": String, "options": List<String>} döner.
  /// Hata durumunda [Exception] fırlatır.
  Future<Map<String, dynamic>> sendMessageToBot(String message) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? token = prefs.getString('access_token');

    if (token == null || token.isEmpty) {
      throw Exception('Oturum bulunamadı. Lütfen tekrar giriş yapın.');
    }

    final Uri url = Uri.parse('$baseUrl/chat');

    try {
      final http.Response response = await http
          .post(
            url,
            headers: <String, String>{
              'Content-Type': 'application/json',
              'accept': 'application/json',
              'Authorization': 'Bearer $token',
            },
            body: jsonEncode(<String, String>{'message': message}),
          )
          .timeout(const Duration(seconds: 60));

      print('[ApiService] sendMessageToBot → ${response.statusCode}');

      if (response.statusCode == 401) {
        await _handle401();
        throw Exception('Oturum süresi doldu.');
      }

      if (response.statusCode == 200) {
        final Map<String, dynamic> data =
            jsonDecode(response.body) as Map<String, dynamic>;
        final String answer = (data['answer'] as String?) ?? 'Yanıt alınamadı.';
        final List<String> options =
            (data['options'] as List<dynamic>?)?.cast<String>() ?? <String>[];
        // Toplantı notu için ek alanlar — null olabilir
        final String? notesText = data['notes_text'] as String?;
        final int? recordId = data['record_id'] as int?;
        return <String, dynamic>{
          'answer': answer,
          'options': options,
          if (notesText != null) 'notes_text': notesText,
          if (recordId != null) 'record_id': recordId,
        };
      }

      if (response.statusCode == 503) {
        throw Exception(
          'Chatbot servisi şu an kullanılamıyor. '
          "Lütfen 'ollama serve' komutunun çalıştığından emin olun.",
        );
      }

      final String detail = (() {
        try {
          return (jsonDecode(response.body)['detail'] as String?) ?? '';
        } catch (_) {
          return '';
        }
      })();
      throw Exception(
        detail.isNotEmpty ? detail : 'Sunucu hatası (${response.statusCode})',
      );
    } on Exception {
      rethrow;
    } catch (e) {
      throw Exception('Bağlantı hatası: $e');
    }
  }
}
