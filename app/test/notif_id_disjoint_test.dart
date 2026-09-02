// 알림 id 도메인 분리 실측 — NotificationService.showInstant는 id=stableId(prefix+key),
// planAlarms는 id=stableId('c:alarm:'+svcid). 통합 전 충돌하던 조합이 실제로 분리됐는지 증명.
//
// (프리픽스는 NotificationService 내부 private이라 여기선 동일 공식을 stableId로 재현해 검증)
import 'package:flutter_test/flutter_test.dart';
import 'package:yeollim_allim/core/notif_types.dart';

// showInstant가 만드는 실제 id 공식
int courseInstantId(String key) => stableId('c:$key');
int eventId(String key) => stableId('e:$key');
// planAlarms가 만드는 실제 알람 id 공식
int courseAlarmId(String svcid) => stableId('c:alarm:$svcid');

void main() {
  test('원래 버그: 강좌·나들이 burst_summary가 같은 id로 서로 덮어쓰던 것 → 분리됨', () {
    expect(courseInstantId('burst_summary') == eventId('burst_summary'), false,
        reason: '통합 전엔 stableId("burst_summary")로 동일 → 한쪽이 덮어씀');
  });

  test('동일 svcid라도 강좌-즉시 / 강좌-알람 / 나들이-즉시 id가 전부 다름', () {
    const svc = 'S12345';
    final ids = {
      courseInstantId('new_$svc'),
      courseAlarmId(svc),
      eventId('new_$svc'),
    };
    expect(ids.length, 3, reason: '세 종류 id가 모두 달라야 서로 안 덮어씀');
  });

  test('강좌 재오픈 vs 신규 vs 알람 id 상호 분리(같은 강좌 lifecycle)', () {
    const svc = 'S999';
    final ids = {
      courseInstantId('new_$svc'),
      courseInstantId('reopen_${svc}_2026-07-03 20:20'),
      courseAlarmId(svc),
    };
    expect(ids.length, 3);
  });

  test('나들이 신규 vs 다이제스트 id 분리', () {
    expect(eventId('new_seoul:ab12') == eventId('digest_2026-W29'), false);
  });

  test('여러 svcid에 걸쳐 강좌-알람 ↔ 나들이-즉시 id 교집합 0(대표 표본)', () {
    final courseAlarms = <int>{};
    final eventNews = <int>{};
    for (var i = 0; i < 200; i++) {
      courseAlarms.add(courseAlarmId('S$i'));
      eventNews.add(eventId('new_seoul:$i'));
    }
    expect(courseAlarms.intersection(eventNews), isEmpty,
        reason: '알람 id 공간과 나들이 즉시 id 공간이 겹치면 안 됨');
  });
}
