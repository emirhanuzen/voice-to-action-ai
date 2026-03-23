import 'package:flutter/material.dart';

import 'record_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  static const String routeName = '/home';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ElevatedButton(
          onPressed: () {
            Navigator.pushNamed(context, RecordScreen.routeName);
          },
          child: const Text('Kayıt Al'),
        ),
      ),
    );
  }
}
