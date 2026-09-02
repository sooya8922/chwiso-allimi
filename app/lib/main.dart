import 'package:flutter/material.dart';

import 'core/background.dart';
import 'core/notification_service.dart';
import 'core/settings_screen.dart';
import 'event/screens/home_screen.dart' as event_home;
import 'event/services/background.dart' as event_bg;
import 'screens/home_screen.dart' as course_home;
import 'services/background.dart' as course_bg;

/// 알림/백그라운드 초기화 오류 — 크래시 대신 홈 배너로 노출(원격 진단용).
/// 두 도메인 홈이 공유한다(현재 탭만 화면에 보이므로 배너는 한 번만 노출).
final ValueNotifier<String?> initError = ValueNotifier(null);

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // 원칙: 어떤 플러그인 초기화도 첫 화면을 막거나 죽이면 안 된다.
  // (chwiso M4 실기기: 시작 시 플러그인 crash → 앱 즉시 종료. UI 먼저, 초기화는 뒤에서.)
  runApp(const MergedApp());
  WidgetsBinding.instance.addPostFrameCallback((_) async {
    try {
      await NotificationService.init();
      await NotificationService.requestPermission();
    } catch (e) {
      initError.value = '알림 초기화 실패: $e';
      return; // 알림 없이도 열람은 가능
    }
    try {
      await registerBackgroundRefresh(); // 강좌+나들이 단일 태스크
    } catch (e) {
      initError.value = '백그라운드 등록 실패: $e';
    }
  });
}

class MergedApp extends StatelessWidget {
  const MergedApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '강좌·나들이 알리미',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF2E7D5B)),
        useMaterial3: true,
      ),
      home: const RootShell(),
    );
  }
}

/// 하단 네비 셸 — [강좌][나들이]. 각 탭은 기존 도메인 홈(자체 AppBar·탭·필터 포함)을
/// 그대로 임베드한다. IndexedStack으로 두 탭 상태를 유지(전환 시 재로딩 없음).
/// '가볼 곳'은 나들이 홈의 내부 탭으로 이미 존재하므로 별도 하단 탭으로 빼지 않는다.
class RootShell extends StatefulWidget {
  /// 테스트에서 네트워크/플러그인 비의존 페이지를 주입하기 위한 오버라이드(프로덕션은 null).
  final List<Widget>? pages;

  const RootShell({super.key, this.pages});

  @override
  State<RootShell> createState() => _RootShellState();
}

class _RootShellState extends State<RootShell> {
  int _index = 0;

  // 각 홈은 자기 도메인 feed 로드 성공 시 자기 도메인 알림만 점검(preloaded로 재사용).
  late final List<Widget> _pages = widget.pages ??
      [
        course_home.HomeScreen(
          onFeedLoaded: (feed) => course_bg.refreshAndNotify(preloaded: feed),
          initError: initError,
        ),
        event_home.HomeScreen(
          onFeedLoaded: (feed) => event_bg.refreshAndNotify(preloaded: feed),
          initError: initError,
        ),
        const SettingsScreen(),
      ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _index, children: _pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.menu_book_outlined),
            selectedIcon: Icon(Icons.menu_book),
            label: '강좌',
          ),
          NavigationDestination(
            icon: Icon(Icons.park_outlined),
            selectedIcon: Icon(Icons.park),
            label: '나들이',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: '설정',
          ),
        ],
      ),
    );
  }
}
