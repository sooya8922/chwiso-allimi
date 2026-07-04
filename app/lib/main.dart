import 'package:flutter/material.dart';

import 'screens/home_screen.dart';

void main() {
  runApp(const YeollimApp());
}

class YeollimApp extends StatelessWidget {
  const YeollimApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '열림알림',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF2E7D5B)),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}
