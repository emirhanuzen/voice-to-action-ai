import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/api_service.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  static const String routeName = '/profile';

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final TextEditingController _nameController = TextEditingController();
  final ApiService _apiService = ApiService();

  String _email = 'Yukleniyor...';
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _loadProfileInfo();
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _loadProfileInfo() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String name = prefs.getString('user_name') ?? 'Kullanici';
    final String mail = prefs.getString('user_email') ?? '-';

    if (!mounted) {
      return;
    }

    setState(() {
      _nameController.text = name;
      _email = mail;
    });
  }

  Future<void> _saveProfile() async {
    if (_isSaving) {
      return;
    }

    setState(() {
      _isSaving = true;
    });

    final Map<String, dynamic> result =
        await _apiService.updateProfile(_nameController.text);

    if (!mounted) {
      return;
    }

    setState(() {
      _isSaving = false;
    });

    final bool success = result['success'] == true;
    final String message = (result['message'] as String?) ??
        (success ? 'Profil guncellendi.' : 'Profil guncellenemedi.');

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: success ? Colors.green.shade600 : Colors.red.shade600,
        content: Text(message),
      ),
    );
  }

  Future<void> _logout() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.clear();

    if (!mounted) {
      return;
    }

    Navigator.pushNamedAndRemoveUntil(
      context,
      '/login',
      (Route<dynamic> route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FF),
      appBar: AppBar(
        title: const Text('Profil'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFE7E9F2)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Tam Isim',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _nameController,
                    textCapitalization: TextCapitalization.words,
                    decoration: InputDecoration(
                      hintText: 'Tam isminizi girin',
                      suffixIcon: TextButton(
                        onPressed: _isSaving ? null : _saveProfile,
                        child: _isSaving
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Text('Kaydet'),
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 46,
                    child: ElevatedButton.icon(
                      onPressed: _isSaving ? null : _saveProfile,
                      icon: _isSaving
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.save_outlined),
                      label: const Text('Guncelle'),
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'E-posta',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 6),
                  Text(_email),
                ],
              ),
            ),
            const Spacer(),
            SizedBox(
              height: 50,
              child: ElevatedButton.icon(
                onPressed: _logout,
                icon: const Icon(Icons.logout_rounded),
                label: const Text('Cikis Yap'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
