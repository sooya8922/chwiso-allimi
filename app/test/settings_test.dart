// 설정 탭 위젯 테스트 — 조용시간/다이제스트 로드·저장, start==end 경고.
// SettingsPrefs는 SharedPreferences 목으로, onApply는 no-op으로 주입해 네트워크/플러그인 비의존.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yeollim_allim/core/settings_prefs.dart';
import 'package:yeollim_allim/core/settings_screen.dart';
import 'package:yeollim_allim/core/time.dart';

Future<void> pumpSettings(WidgetTester tester) async {
  await tester.pumpWidget(MaterialApp(
    home: SettingsScreen(prefs: SettingsPrefs(), onApply: () async {}),
  ));
  await tester.pumpAndSettle(); // _load 완료 대기
}

void main() {
  testWidgets('기본값 렌더 — 조용시간 ON, 다이제스트 ON', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await pumpSettings(tester);
    expect(find.text('조용시간 사용'), findsOneWidget);
    expect(find.text('🧺 주말 다이제스트'), findsOneWidget);
    // 기본 스위치는 모두 ON
    final switches = tester.widgetList<SwitchListTile>(find.byType(SwitchListTile));
    expect(switches.every((s) => s.value == true), true);
  });

  testWidgets('다이제스트 토글 → digest_enabled_v1 저장', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await pumpSettings(tester);
    await tester.tap(find.text('🧺 주말 다이제스트'));
    await tester.pumpAndSettle();
    final sp = await SharedPreferences.getInstance();
    expect(sp.getBool('digest_enabled_v1'), false);
  });

  testWidgets('조용시간 끄기 → quiet_config_v1 저장(enabled:false)', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await pumpSettings(tester);
    await tester.tap(find.text('조용시간 사용'));
    await tester.pumpAndSettle();
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getString('quiet_config_v1');
    expect(raw, isNotNull);
    expect((json.decode(raw!) as Map)['enabled'], false);
  });

  testWidgets('start==end면 경고 문구 노출', (tester) async {
    SharedPreferences.setMockInitialValues({
      'quiet_config_v1': json.encode(const QuietConfig(startHour: 22, endHour: 22).toJson()),
    });
    await pumpSettings(tester);
    expect(find.textContaining('적용되지 않아요'), findsOneWidget);
  });
}
