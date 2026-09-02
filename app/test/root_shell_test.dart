import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yeollim_allim/main.dart';

/// 통합 셸(하단 네비) 검증 — 도메인 홈/설정은 각자 테스트가 커버하므로 여기선 네트워크/플러그인
/// 비의존 플레이스홀더를 주입해 '탭 구성 + 전환(IndexedStack)' 로직만 격리 검증한다.
void main() {
  Widget shell() => const MaterialApp(
        home: RootShell(
          pages: [
            Center(child: Text('COURSE_PAGE')),
            Center(child: Text('EVENT_PAGE')),
            Center(child: Text('SETTINGS_PAGE')),
          ],
        ),
      );

  testWidgets('하단 네비 3탭(강좌·나들이·설정) 노출, 초기 탭=강좌', (tester) async {
    await tester.pumpWidget(shell());
    expect(find.text('강좌'), findsOneWidget);
    expect(find.text('나들이'), findsOneWidget);
    expect(find.text('설정'), findsOneWidget);
    final bar = tester.widget<NavigationBar>(find.byType(NavigationBar));
    expect(bar.selectedIndex, 0);
    expect(find.text('COURSE_PAGE'), findsOneWidget);
  });

  testWidgets('나들이·설정 탭 전환 시 선택 인덱스 반영', (tester) async {
    await tester.pumpWidget(shell());
    await tester.tap(find.text('나들이'));
    await tester.pump();
    expect(tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex, 1);
    await tester.tap(find.text('설정'));
    await tester.pump();
    expect(tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex, 2);
  });
}
