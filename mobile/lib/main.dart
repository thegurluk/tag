import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'features/map/map_screen.dart';

void main() {
  runApp(const ProviderScope(child: LocationAlertApp()));
}

class LocationAlertApp extends StatelessWidget {
  const LocationAlertApp({super.key});

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFF1F7A5A);

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Yol Bilgi',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: seed,
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: const Color(0xFFF6F7F4),
        appBarTheme: const AppBarTheme(centerTitle: false),
      ),
      home: const MapScreen(),
    );
  }
}
