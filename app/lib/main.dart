import 'package:flutter/material.dart';

import 'screens/home_screen.dart';
import 'services/background.dart';
import 'services/notification_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await NotificationService.init();
  // 알림 권한(Android 13+) — 거부해도 앱은 열람용으로 정상 동작
  await NotificationService.requestPermission();
  await registerBackgroundRefresh();
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
      // 앱을 열 때마다 최신 feed로 즉시알림 점검 + 광클 알람 재예약
      home: HomeScreen(onFeedLoaded: (feed) => refreshAndNotify(preloaded: feed)),
    );
  }
}
