import 'package:flutter/material.dart';

/// Uygulamanın tek navigatorKey'i.
/// main.dart → MaterialApp.navigatorKey
/// api_service.dart → 401 yönlendirmesi
final GlobalKey<NavigatorState> appNavigatorKey =
    GlobalKey<NavigatorState>(debugLabel: 'appNavigator');
