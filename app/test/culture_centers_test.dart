// 문화센터 바로가기 화면 — 6곳 노출 + 면책문 존재 확인.
// (강좌 데이터를 다루지 않는 정적 링크 화면이라 로직 테스트는 렌더/문구 위주)
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yeollim_allim/screens/culture_centers_screen.dart';

void main() {
  testWidgets('6개 문화센터가 모두 노출된다', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: CultureCentersScreen()));
    for (final name in ['홈플러스 문화센터', '이마트 컬처클럽', '현대백화점 문화센터', '롯데백화점 문화센터',
      '롯데마트 문화센터', '신세계 아카데미']) {
      expect(find.text(name), findsOneWidget, reason: '$name 누락');
    }
  });

  testWidgets('안내문 + 면책문이 표시된다(약관 방어)', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: CultureCentersScreen()));
    expect(find.textContaining('공식 페이지로 바로 이동'), findsOneWidget);
    expect(find.textContaining('강좌 정보를 수집·제공하지 않습니다'), findsOneWidget);
  });

  testWidgets('링크 탭 시 크래시 없음(launchUrl 미가용 테스트환경서도 방어)', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: CultureCentersScreen()));
    await tester.tap(find.text('홈플러스 문화센터'));
    await tester.pumpAndSettle();
    // 예외를 삼키고 스낵바로 처리 → 위젯 트리 살아있음
    expect(find.text('홈플러스 문화센터'), findsOneWidget);
  });
}
