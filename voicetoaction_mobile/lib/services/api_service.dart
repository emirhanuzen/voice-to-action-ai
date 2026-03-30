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

  Future<String?> uploadMediaAndTranscribe(File file) async {
    final Uri url = Uri.parse('$baseUrl/transcribe');

    try {
      final http.MultipartRequest request = http.MultipartRequest('POST', url)
        ..files.add(await http.MultipartFile.fromPath('file', file.path));

      final http.StreamedResponse streamedResponse = await request.send();
      final String responseBody = await streamedResponse.stream.bytesToString();

      if (streamedResponse.statusCode == 200) {
        final Map<String, dynamic> data =
            jsonDecode(responseBody) as Map<String, dynamic>;
        return data['text'] as String?;
      }

      print(
        'Transcribe failed. Status: ${streamedResponse.statusCode}, '
        'Body: $responseBody',
      );
      return null;
    } catch (e) {
      print('Transcribe request error: $e');
      return null;
    }
  }
}
