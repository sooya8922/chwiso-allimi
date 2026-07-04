import 'package:flutter/material.dart';

import 'screens/home_screen.dart';
import 'services/background.dart';
import 'services/notification_service.dart';

/// 알림/백그라운드 초기화 오류 — 크래시 대신 홈 배너로 노출(원격 진단용).
final ValueNotifier<String?> initError = ValueNotifier(null);

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // 원칙: 어떤 플러그인 초기화도 첫 화면을 막거나 죽이면 안 된다.
  // (실기기 M4에서 발견: 시작 시 플러그인 crash → 앱 즉시 종료. UI 먼저, 초기화는 뒤에서.)
  runApp(const YeollimApp());
  WidgetsBinding.instance.addPostFrameCallback((_) async {
    try {
      await NotificationService.init();
      await NotificationService.requestPermission();
    } catch (e) {
      initError.value = '알림 초기화 실패: $e';
      return; // 알림 없이도 열람은 가능
    }
    try {
      await registerBackgroundRefresh();
    } catch (e) {
      initError.value = '백그라운드 등록 실패: $e';
    }
  });
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
      // 앱을 열 때마다 최신 feed로 즉시알림 점검 + 광클 알람 재예약.
      // 초기화가 아직 안 끝났거나 실패했어도 여기 안에서 안전하게 처리된다(호출측이 삼킴).
      home: HomeScreen(
        onFeedLoaded: (feed) => refreshAndNotify(preloaded: feed),
        initError: initError,
      ),
    );
  }
}
