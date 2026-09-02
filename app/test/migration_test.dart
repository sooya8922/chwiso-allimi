// 마이그레이션 실측 — v1.0(강좌 전용) 사용자가 통합 v1.1로 업그레이드할 때
// 기존 상태(구독/조용시간/이미 본 알림)가 보존되고, 나들이는 신규로 깨끗하게 시작하는지.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yeollim_allim/core/settings_prefs.dart';
import 'package:yeollim_allim/event/services/prefs_service.dart' as event_prefs;
import 'package:yeollim_allim/services/prefs_service.dart' as course_prefs;

void main() {
  test('v1.0 강좌 사용자 업그레이드 — 강좌 구독/조용시간 보존, 나들이 신규 시작', () async {
    // v1.0 사용자의 실제 저장 상태(옛 키만 존재)
    SharedPreferences.setMockInitialValues({
      'subscription_v1': json.encode({
        'areas': ['마포구'],
        'freeOnly': true,
        'targets': ['kids'],
        'keywords': ['원예'],
      }),
      'quiet_config_v1': json.encode({
        'enabled': true,
        'startHour': 23,
        'endHour': 7,
        'alarmsExempt': false,
      }),
      'notified_keys_v1': json.encode(['new_S1', 'new_S2']),
    });

    // ① 강좌 구독조건 보존 (subscription_v1 그대로 읽힘)
    final csub = await course_prefs.PrefsService().load();
    expect(csub.areas, {'마포구'});
    expect(csub.freeOnly, true);
    expect(csub.targets, {'kids'});
    expect(csub.keywords, ['원예']);

    // ② 공유 조용시간 보존 (설정 탭이 읽는 SettingsPrefs가 같은 키로 읽음)
    final q = await SettingsPrefs().loadQuiet();
    expect(q.enabled, true);
    expect(q.startHour, 23);
    expect(q.endHour, 7);
    expect(q.alarmsExempt, false, reason: 'alarmsExempt까지 왕복 보존');

    // ③ 이미 본 강좌 알림 키 보존 (업그레이드 후 재알림 폭탄 없음)
    final sp = await SharedPreferences.getInstance();
    expect(sp.getString('notified_keys_v1'), isNotNull);

    // ④ 나들이는 기존 키가 없으므로 신규(기본값)로 깨끗하게 시작
    final esub = await event_prefs.PrefsService().load();
    expect(esub.areas, isEmpty);
    expect(esub.kidOnly, true, reason: '나들이 기본=아이만 ON');
    expect(esub.freeOnly, false);
    expect(await SettingsPrefs().loadDigestEnabled(), true, reason: '다이제스트 기본 ON');
    expect(sp.getString('notified_keys_event_v1'), isNull,
        reason: '나들이 알림상태는 첫 실행 baseline으로 채워질 것(폭탄 방지)');
  });

  test('완전 신규 설치 — 모든 도메인 기본값', () async {
    SharedPreferences.setMockInitialValues({});
    final csub = await course_prefs.PrefsService().load();
    final esub = await event_prefs.PrefsService().load();
    expect(csub.isEmpty, true);
    expect(esub.isDefault, true);
    expect((await SettingsPrefs().loadQuiet()).enabled, true);
    expect(await SettingsPrefs().loadDigestEnabled(), true);
  });
}
