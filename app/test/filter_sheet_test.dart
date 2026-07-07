// FilterSheet 위젯 테스트 — 키워드 파싱, 조용시간 토글/시각, 초기화 (커버리지 0%였던 영역).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yeollim_allim/logic/matcher.dart';
import 'package:yeollim_allim/logic/notif_planner.dart';
import 'package:yeollim_allim/widgets/filter_sheet.dart';

Future<FilterResult?> openAndApply(
  WidgetTester tester, {
  Subscription initial = const Subscription(),
  QuietConfig quiet = const QuietConfig(),
  Future<void> Function(WidgetTester t)? interact,
}) async {
  FilterResult? result;
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (ctx) => ElevatedButton(
          onPressed: () async {
            result = await showModalBottomSheet<FilterResult>(
              context: ctx,
              isScrollControlled: true,
              builder: (_) => FilterSheet(
                  initial: initial, initialQuiet: quiet, availableAreas: const ['마포구', '강서구']),
            );
          },
          child: const Text('open'),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  if (interact != null) await interact(tester);
  await tester.tap(find.text('적용'));
  await tester.pumpAndSettle();
  return result;
}

void main() {
  testWidgets('키워드 파싱: 쉼표+공백 혼용 분리, 빈 항목 제거', (tester) async {
    final r = await openAndApply(tester, interact: (t) async {
      await t.enterText(find.byType(TextField), '방학, 원예  목공,, ');
      await t.pumpAndSettle();
    });
    expect(r!.sub.keywords, ['방학', '원예', '목공'], reason: '빈 토큰/중복 구분자 제거');
  });

  testWidgets('초기 구독조건이 UI에 반영되고 그대로 반환', (tester) async {
    const init = Subscription(areas: {'마포구'}, freeOnly: true, keywords: ['체험']);
    final r = await openAndApply(tester, initial: init);
    expect(r!.sub.areas, {'마포구'});
    expect(r.sub.freeOnly, true);
    expect(r.sub.keywords, ['체험']);
  });

  testWidgets('무료 스위치 토글', (tester) async {
    final r = await openAndApply(tester, interact: (t) async {
      await t.tap(find.text('무료만'));
      await t.pumpAndSettle();
    });
    expect(r!.sub.freeOnly, true);
  });

  testWidgets('지역 칩 선택', (tester) async {
    final r = await openAndApply(tester, interact: (t) async {
      final chip = find.widgetWithText(FilterChip, '강서구');
      await t.ensureVisible(chip); // 시트 하단이라 스크롤로 노출
      await t.pumpAndSettle();
      await t.tap(chip);
      await t.pumpAndSettle();
    });
    expect(r!.sub.areas, {'강서구'});
  });

  testWidgets('조용시간 끄면 알람 예외 스위치 비활성', (tester) async {
    final r = await openAndApply(tester, interact: (t) async {
      final sw = find.text('조용시간 사용'); // 시트 최하단(지연 로딩) → scrollUntilVisible
      await t.scrollUntilVisible(sw, 300, scrollable: find.byType(Scrollable).first);
      await t.pumpAndSettle();
      await t.tap(sw); // ON→OFF
      await t.pumpAndSettle();
    });
    expect(r!.quiet.enabled, false);
  });

  testWidgets('MINOR-2: feed에 없는 저장 지역(유령)은 제거되어 반환', (tester) async {
    // '도봉구'는 availableAreas(마포/강서)에 없음 → 교집합으로 걸러져야
    const init = Subscription(areas: {'마포구', '도봉구'});
    final r = await openAndApply(tester, initial: init);
    expect(r!.sub.areas, {'마포구'}, reason: '유령 지역 도봉구 제거');
  });

  testWidgets('MEDIUM-2: 조용시간 start==end면 경고 문구 노출', (tester) async {
    await openAndApply(tester,
        quiet: const QuietConfig(startHour: 22, endHour: 22),
        interact: (t) async {
      final warn = find.textContaining('적용되지 않아요');
      await t.scrollUntilVisible(warn, 300, scrollable: find.byType(Scrollable).first);
      expect(warn, findsOneWidget);
    });
  });

  testWidgets('초기화 버튼 → 모든 조건 리셋', (tester) async {
    const init = Subscription(areas: {'마포구'}, freeOnly: true, keywords: ['체험']);
    final r = await openAndApply(tester, initial: init, interact: (t) async {
      await t.tap(find.text('초기화'));
      await t.pumpAndSettle();
    });
    expect(r!.sub.isEmpty, true);
    expect(r.quiet.enabled, true, reason: '초기화는 조용시간도 기본값으로');
  });
}
