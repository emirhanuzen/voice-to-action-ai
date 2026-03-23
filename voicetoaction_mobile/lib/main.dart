import 'package:flutter/material.dart';

import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'screens/record_screen.dart';
import 'screens/splash_screen.dart';

void main() {
  runApp(const VoiceToActionApp());
}

class VoiceToActionApp extends StatelessWidget {
  const VoiceToActionApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Voice To Action',
      initialRoute: SplashScreen.routeName,
      routes: {
        SplashScreen.routeName: (_) => const SplashScreen(),
        LoginScreen.routeName: (_) => const LoginScreen(),
        HomeScreen.routeName: (_) => const HomeScreen(),
        RecordScreen.routeName: (_) => const RecordScreen(),
      },
    );
  }
}
