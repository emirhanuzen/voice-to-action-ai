import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class ApiService {
  static const String baseUrl =
      'http://10.0.2.2:8000/api'; // Tek bir /api icermeli.

  Future<Map<String, dynamic>> login(String email, String password) async {
    final Uri url = Uri.parse('$baseUrl/login');

    try {
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
          'Login failed. Status: ${response.statusCode}, '
          'Body: ${response.body}, Detail: $message',
        );
        return <String, dynamic>{
          'success': false,
          'message': message,
        };
      }

      final Map<String, dynamic> data =
          jsonDecode(response.body) as Map<String, dynamic>;
      final String? accessToken = data['access_token'] as String?;

      if (accessToken != null && accessToken.isNotEmpty) {
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
        return <String, dynamic>{'success': true};
      }

      print('Login failed. access_token missing. Body: ${response.body}');
      return <String, dynamic>{
        'success': false,
        'message': 'Access token bulunamadi.',
      };
    } catch (e) {
      print('Login request error: $e');
      return <String, dynamic>{
        'success': false,
        'message': 'Login request error: $e',
      };
    }
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

  /// Returns `{'text': String, 'tasks': List<dynamic>}` on success, null on failure.
  Future<Map<String, dynamic>?> uploadMediaAndTranscribe(
    File file, {
    String category = 'Diğer',
  }) async {
    final Uri url = Uri.parse('$baseUrl/transcribe');

    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final int userId = prefs.getInt('user_id') ?? 0;

    print('[ApiService] uploadMediaAndTranscribe → URL: $url');
    print('[ApiService] user_id=$userId  kategori=$category  '
        'dosya=${file.path}');

    if (userId == 0) {
      print('[ApiService] UYARI: user_id=0. '
          'Kullanıcı giriş yapmamış veya SharedPreferences boş olabilir.');
    }

    try {
      final http.MultipartRequest request = http.MultipartRequest('POST', url)
        ..fields['category'] = category
        ..fields['user_id'] = userId.toString()
        ..files.add(await http.MultipartFile.fromPath('file', file.path));

      print('[ApiService] Gönderilen form alanları: ${request.fields}');

      final http.StreamedResponse streamedResponse = await request.send();
      final String responseBody = await streamedResponse.stream.bytesToString();

      print('[ApiService] Transcribe yanıt kodu: '
          '${streamedResponse.statusCode}');
      print('[ApiService] Transcribe yanıt body: '
          '${responseBody.length > 300 ? responseBody.substring(0, 300) : responseBody}');

      if (streamedResponse.statusCode == 200) {
        final Map<String, dynamic> data =
            jsonDecode(responseBody) as Map<String, dynamic>;
        return <String, dynamic>{
          'text': (data['text'] as String?) ?? '',
          'tasks': (data['tasks'] as List<dynamic>?) ?? <dynamic>[],
          'record_id': data['record_id'],
        };
      }

      print('[ApiService] HATA ${streamedResponse.statusCode}: $responseBody');
      return null;
    } catch (e, stack) {
      print('[ApiService] Transcribe istek hatası: $e');
      print('[ApiService] Stack trace: $stack');
      return null;
    }
  }

  /// GET /api/records/{user_id} — kullanıcının geçmiş transkripsiyon kayıtları.
  Future<List<Map<String, dynamic>>> getRecords() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? token = prefs.getString('access_token');
    final int userId = prefs.getInt('user_id') ?? 0;

    print('[ApiService] getRecords → user_id=$userId');

    if (userId == 0) {
      print('[ApiService] getRecords ATLANDI: user_id=0');
      return <Map<String, dynamic>>[];
    }

    final Uri url = Uri.parse('$baseUrl/records/$userId');
    print('[ApiService] getRecords URL: $url');

    try {
      final http.Response response = await http.get(
        url,
        headers: <String, String>{
          'accept': 'application/json',
          if (token != null && token.isNotEmpty)
            'Authorization': 'Bearer $token',
        },
      );

      print('[ApiService] getRecords yanıt kodu: ${response.statusCode}');

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body) as List<dynamic>;
        print('[ApiService] getRecords: ${data.length} kayıt döndü.');
        return data.whereType<Map<String, dynamic>>().toList();
      }

      print('[ApiService] getRecords HATA ${response.statusCode}: '
          '${response.body}');
      return <Map<String, dynamic>>[];
    } catch (e, stack) {
      print('[ApiService] getRecords istek hatası: $e\n$stack');
      return <Map<String, dynamic>>[];
    }
  }

  /// GET /api/tasks/{user_id} — kullanıcının NLP ile çıkarılmış görevleri.
  Future<List<Map<String, dynamic>>> getTasks() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? token = prefs.getString('access_token');
    final int userId = prefs.getInt('user_id') ?? 0;

    print('[ApiService] getTasks → user_id=$userId');

    if (userId == 0) {
      print('[ApiService] getTasks ATLANDI: user_id=0');
      return <Map<String, dynamic>>[];
    }

    final Uri url = Uri.parse('$baseUrl/tasks/$userId');
    print('[ApiService] getTasks URL: $url');

    try {
      final http.Response response = await http.get(
        url,
        headers: <String, String>{
          'accept': 'application/json',
          if (token != null && token.isNotEmpty)
            'Authorization': 'Bearer $token',
        },
      );

      print('[ApiService] getTasks yanıt kodu: ${response.statusCode}');

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body) as List<dynamic>;
        print('[ApiService] getTasks: ${data.length} görev döndü.');
        return data.whereType<Map<String, dynamic>>().toList();
      }

      print('[ApiService] getTasks HATA ${response.statusCode}: '
          '${response.body}');
      return <Map<String, dynamic>>[];
    } catch (e, stack) {
      print('[ApiService] getTasks istek hatası: $e\n$stack');
      return <Map<String, dynamic>>[];
    }
  }
}
