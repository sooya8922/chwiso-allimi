// 알림 플래너 단위테스트 — 중복발송/과거오픈/조건매칭/상한/보정 등 엣지케이스 고정.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart' hide matches;
import 'package:yeollim_allim/logic/matcher.dart';
import 'package:yeollim_allim/logic/notif_planner.dart';
import 'package:yeollim_allim/models/course.dart';

Feed feedFrom(Map<String, dynamic> partial) => Feed.fromJson({
      'version': 1,
      'generated_at': '2026-07-04 13:00:00',
      'courses': [],
      'new': [],
      'reopened': [],
      'upcoming': [],
      ...partial,
    });

Map<String, dynamic> course(String id,
        {String area = '마포구',
        String status = '접수중',
        String pay = '무료',
        String name = '강좌',
        String url = 'https://yeyak.seoul.go.kr/x'}) =>
    {
      'id': id, 'name': name, 'area': area, 'cat': '문화체험', 'status': status,
      'pay': pay, 'target': '', 'rcpt_bgn': '', 'rcpt_end': '', 'x': '', 'y': '',
      'url': url, 'img': '',
    };

void main() {
  final now = DateTime(2026, 7, 4, 13, 0);

  group('즉시 알림(신규)', () {
    test('기본: 신규 1건 → 알림 1건, 딥링크 포함', () {
      final f = feedFrom({
        'courses': [course('S1', name: '새강좌')],
        'new': [{'id': 'S1', 'name': '새강좌', 'area': '마포구', 'status': '접수중', 'seen_at': '2026-07-04 09:00'}],
      });
      final out = planInstantNotifications(f, const Subscription(), {}).toShow;
      expect(out.length, 1);
      expect(out[0].key, 'new_S1');
      expect(out[0].url, contains('yeyak'));
    });

    test('엣지: 이미 알린 키는 재발송 안 함', () {
      final f = feedFrom({
        'courses': [course('S1')],
        'new': [{'id': 'S1', 'name': 'x', 'area': '', 'status': '접수중', 'seen_at': ''}],
      });
      expect(planInstantNotifications(f, const Subscription(), {'new_S1'}).toShow, isEmpty);
    });

    test('엣지: 구독조건 불일치 신규는 스킵', () {
      final f = feedFrom({
        'courses': [course('S1', area: '강남구')],
        'new': [{'id': 'S1', 'name': 'x', 'area': '강남구', 'status': '접수중', 'seen_at': ''}],
      });
      expect(planInstantNotifications(f, const Subscription(areas: {'마포구'}), {}).toShow, isEmpty);
    });

    test('엣지: courses에 없는 신규(고아) — 조건 없으면 발송, 있으면 보수적 스킵', () {
      final f = feedFrom({
        'new': [{'id': 'S9', 'name': '고아', 'area': '', 'status': '접수중', 'seen_at': ''}],
      });
      expect(planInstantNotifications(f, const Subscription(), {}).toShow.length, 1);
      expect(planInstantNotifications(f, const Subscription(freeOnly: true), {}).toShow, isEmpty);
    });
  });

  group('즉시 알림(재오픈)', () {
    Map<String, dynamic> reopen(String id, {int inWindow = 1}) =>
        {'id': id, 'name': 'r', 'area': '마포구', 'in_window': inWindow, 'at': '2026-07-03 20:20'};

    test('기본: in_window 재오픈 + 현재 접수중 → 알림', () {
      final f = feedFrom({'courses': [course('S1')], 'reopened': [reopen('S1')]});
      final out = planInstantNotifications(f, const Subscription(), {}).toShow;
      expect(out.length, 1);
      expect(out[0].key, startsWith('reopen_S1'));
    });

    test('엣지: 접수기간 밖(in_window=0) 재오픈은 스킵', () {
      final f = feedFrom({'courses': [course('S1')], 'reopened': [reopen('S1', inWindow: 0)]});
      expect(planInstantNotifications(f, const Subscription(), {}).toShow, isEmpty);
    });

    test('엣지: 재오픈 후 이미 다시 마감된 강좌는 스킵(헛알림 방지)', () {
      final f = feedFrom({'courses': [course('S1', status: '예약마감')], 'reopened': [reopen('S1')]});
      expect(planInstantNotifications(f, const Subscription(), {}).toShow, isEmpty);
    });
  });

  group('광클 알람', () {
    Map<String, dynamic> up(String id, String openAt, {String area = '마포구'}) =>
        {'id': id, 'name': 'u', 'area': area, 'open_at': openAt, 'lead_min': 999};

    test('기본: 오픈 10분 전 예약 + 시각 오름차순', () {
      final f = feedFrom({
        'courses': [course('S1'), course('S2')],
        'upcoming': [up('S2', '2026-07-06 14:00'), up('S1', '2026-07-06 10:00')],
      });
      final out = planAlarms(f, const Subscription(), now);
      expect(out.length, 2);
      expect(out[0].svcid, 'S1');
      expect(out[0].at, DateTime(2026, 7, 6, 9, 50));
      expect(out[0].title, contains('10:00'));
    });

    test('엣지: 과거 오픈은 제외', () {
      final f = feedFrom({'upcoming': [up('S1', '2026-07-04 12:00')]});
      expect(planAlarms(f, const Subscription(), now), isEmpty);
    });

    test('엣지: 10분 미만 남음 → now+15초로 보정(놓치지 않음)', () {
      final f = feedFrom({'upcoming': [up('S1', '2026-07-04 13:05')]});
      final out = planAlarms(f, const Subscription(), now);
      expect(out.length, 1);
      expect(out[0].at, now.add(const Duration(seconds: 15)));
    });

    test('엣지: 파싱 불가 open_at은 제외(크래시 없음)', () {
      final f = feedFrom({'upcoming': [up('S1', '이상한값')]});
      expect(planAlarms(f, const Subscription(), now), isEmpty);
    });

    test('엣지: 상한 초과 시 가까운 순으로 자름', () {
      final ups = List.generate(maxScheduledAlarms + 20,
          (i) => up('S$i', '2026-07-${(5 + i % 20).toString().padLeft(2, '0')} 10:00'));
      final f = feedFrom({'upcoming': ups});
      final out = planAlarms(f, const Subscription(), now);
      expect(out.length, maxScheduledAlarms);
      // 가장 먼 것이 잘렸는지: 남은 알람의 최대시각 < 전체 최대시각
      expect(out.last.at.isBefore(DateTime(2026, 7, 24, 10, 0)), true);
    });

    test('엣지: 구독조건 필터 적용', () {
      final f = feedFrom({
        'courses': [course('S1', area: '강남구'), course('S2', area: '마포구')],
        'upcoming': [up('S1', '2026-07-06 10:00', area: '강남구'), up('S2', '2026-07-06 10:00')],
      });
      final out = planAlarms(f, const Subscription(areas: {'마포구'}), now);
      expect(out.length, 1);
      expect(out[0].svcid, 'S2');
    });
  });

  group('stableId', () {
    test('결정적 + 양수 + 충돌 낮음', () {
      expect(stableId('S123'), stableId('S123'));
      expect(stableId('S123') == stableId('S124'), false);
      final ids = List.generate(2000, (i) => stableId('S26061912345$i')).toSet();
      expect(ids.length, greaterThan(1990), reason: '2000개 중 충돌 10개 미만');
      expect(ids.every((i) => i > 0), true);
    });
  });

  group('재오픈 중복 방지(M4 실기기 버그 고정)', () {
    Map<String, dynamic> reopenAt(String id, String at) =>
        {'id': id, 'name': 'r', 'area': '강남구', 'in_window': 1, 'at': at};

    test('같은 강좌 이벤트 3건(대모산 케이스) → 최신 1건만 발송', () {
      final f = feedFrom({
        'courses': [course('S1')],
        'reopened': [reopenAt('S1', '2026-06-29 14:51'), reopenAt('S1', '2026-07-05 18:48'),
                     reopenAt('S1', '2026-07-02 10:16')],
      });
      final plan = planInstantNotifications(f, const Subscription(), {});
      expect(plan.toShow.length, 1);
      expect(plan.toShow[0].key, 'reopen_S1_2026-07-05 18:48');
      // allKeys에는 3건 전부 (억제된 것도 '본 것'으로)
      expect(plan.allKeys.where((k) => k.startsWith('reopen_S1_')).length, 3);
    });

    test('쿨다운: 같은 강좌의 이전 이벤트를 이미 알렸으면 새 이벤트 억제', () {
      final f = feedFrom({
        'courses': [course('S1')],
        'reopened': [reopenAt('S1', '2026-07-05 18:48')],
      });
      final plan = planInstantNotifications(
          f, const Subscription(), {'reopen_S1_2026-07-02 10:16'});
      expect(plan.toShow, isEmpty, reason: '이전 이벤트 키가 남아있는 동안 재알림 금지');
    });

    test('쿨다운 해제: 이전 이벤트가 7일 지나 feed에서 빠지면(키 정리 후) 새 이벤트 발송', () {
      // 호출측이 allKeys만 저장하므로, 사라진 이벤트 키는 자동 정리된 상태를 시뮬레이션
      final f = feedFrom({
        'courses': [course('S1')],
        'reopened': [reopenAt('S1', '2026-07-20 10:00')],
      });
      final plan = planInstantNotifications(f, const Subscription(), <String>{});
      expect(plan.toShow.length, 1);
    });

    test('첫 실행 시맨틱: allKeys는 조건 불일치·마감 이벤트도 전부 포함', () {
      final f = feedFrom({
        'courses': [course('S1', area: '강남구'), course('S2', status: '예약마감')],
        'new': [{'id': 'S1', 'name': 'x', 'area': '강남구', 'status': '접수중', 'seen_at': ''}],
        'reopened': [reopenAt('S2', '2026-07-05 10:00')],
      });
      final plan = planInstantNotifications(f, const Subscription(areas: {'마포구'}), {});
      expect(plan.toShow, isEmpty);
      expect(plan.allKeys, {'new_S1', 'reopen_S2_2026-07-05 10:00'},
          reason: '억제된 이벤트도 기준선에 저장 — 조건 변경 시 소급 발화 방지');
    });
  });

  group('leadLabel — 기기 시각 기준(M4 "3시간 후" 표시 버그 고정)', () {
    final now = DateTime(2026, 7, 6, 8, 58); // 사용자가 본 그 시각
    test('실측 케이스: 09:00 오픈을 08:58에 보면 2분 후 (3시간 후 아님!)', () {
      expect(leadLabel(DateTime(2026, 7, 6, 9, 0), now), '2분 후');
    });
    test('엣지: 이미 지난 오픈 → 오픈!', () {
      expect(leadLabel(DateTime(2026, 7, 6, 8, 0), now), '오픈!');
      expect(leadLabel(DateTime(2026, 7, 6, 8, 58), now), '오픈!', reason: '정확히 지금도 오픈');
    });
    test('엣지: 시간/일 단위 라벨', () {
      expect(leadLabel(DateTime(2026, 7, 6, 10, 0), now), '1시간 후');
      expect(leadLabel(DateTime(2026, 7, 8, 9, 0), now), '2일 후');
    });
    test('엣지: null(파싱 불가) → 빈 문자열', () {
      expect(leadLabel(null, now), '');
    });
  });

  group('알람 제목 날짜 라벨', () {
    Map<String, dynamic> up2(String id, String openAt) =>
        {'id': id, 'name': 'u', 'area': '마포구', 'open_at': openAt, 'lead_min': 999};
    test('절대 날짜(M/D) 표기 — 상대 표현은 발화 시점에 거짓말이 되는 엣지', () {
      final f = feedFrom({
        'courses': [course('S1'), course('S2'), course('S3')],
        'upcoming': [up2('S1', '2026-07-04 14:00'), up2('S2', '2026-07-05 10:00'),
                     up2('S3', '2026-07-20 10:00')],
      });
      final out = planAlarms(f, const Subscription(), now);
      expect(out[0].title, contains('7/4 14:00'));
      expect(out[1].title, contains('7/5 10:00'));
      expect(out[2].title, contains('7/20 10:00'));
    });
    test('엣지: 자정 오픈 — 전날 23:50에 울려도 날짜가 명확', () {
      final f = feedFrom({
        'courses': [course('S1')],
        'upcoming': [up2('S1', '2026-07-05 00:00')],
      });
      final out = planAlarms(f, const Subscription(), DateTime(2026, 7, 4, 20, 0));
      expect(out.length, 1);
      expect(out[0].title, contains('7/5 00:00'));
      expect(out[0].at, DateTime(2026, 7, 4, 23, 50));
    });
  });

  group('inQuietHours 경계', () {
    test('기본(22~8): 경계값', () {
      expect(inQuietHours(DateTime(2026, 7, 6, 21, 59)), false);
      expect(inQuietHours(DateTime(2026, 7, 6, 22, 0)), true);
      expect(inQuietHours(DateTime(2026, 7, 7, 5, 56)), true, reason: '새벽 실측 케이스');
      expect(inQuietHours(DateTime(2026, 7, 7, 7, 59)), true);
      expect(inQuietHours(DateTime(2026, 7, 7, 8, 0)), false);
      expect(inQuietHours(DateTime(2026, 7, 7, 0, 0)), true, reason: '자정');
    });
    test('엣지: 자정 안 걸치는 창(13~18)', () {
      const c = QuietConfig(startHour: 13, endHour: 18);
      expect(inQuietHours(DateTime(2026, 7, 6, 12, 59), c), false);
      expect(inQuietHours(DateTime(2026, 7, 6, 13, 0), c), true);
      expect(inQuietHours(DateTime(2026, 7, 6, 17, 59), c), true);
      expect(inQuietHours(DateTime(2026, 7, 6, 18, 0), c), false);
      expect(inQuietHours(DateTime(2026, 7, 6, 23, 0), c), false);
    });
    test('엣지: enabled=false → 항상 활성', () {
      const c = QuietConfig(enabled: false);
      expect(inQuietHours(DateTime(2026, 7, 7, 3, 0), c), false);
    });
    test('엣지: start==end → 빈 창(조용시간 없음)', () {
      const c = QuietConfig(startHour: 9, endHour: 9);
      expect(inQuietHours(DateTime(2026, 7, 7, 9, 0), c), false);
      expect(inQuietHours(DateTime(2026, 7, 7, 3, 0), c), false);
    });
    test('QuietConfig 직렬화 왕복 + 파손 방어', () {
      const c = QuietConfig(enabled: false, startHour: 23, endHour: 6, alarmsExempt: false);
      final r = QuietConfig.fromJson(c.toJson());
      expect((r.enabled, r.startHour, r.endHour, r.alarmsExempt), (false, 23, 6, false));
      final broken = QuietConfig.fromJson(const {'startHour': 99});
      expect(broken.startHour, 23, reason: '범위 밖 값은 clamp');
      expect(broken.enabled, true, reason: '누락 필드는 기본값');
    });
  });

  group('applyQuietToAlarms', () {
    PlannedAlarm mkAlarm(String id, DateTime at) =>
        PlannedAlarm(id: 1, svcid: id, at: at, title: 't', body: 'b', url: '');
    final alarms = [
      mkAlarm('A', DateTime(2026, 7, 7, 9, 50)),   // 주간
      mkAlarm('B', DateTime(2026, 7, 6, 23, 50)),  // 조용시간(자정 오픈용)
    ];
    test('alarmsExempt=true(기본): 전부 유지', () {
      expect(applyQuietToAlarms(alarms, const QuietConfig()).length, 2);
    });
    test('alarmsExempt=false: 조용시간 발화분 제거', () {
      final out = applyQuietToAlarms(alarms, const QuietConfig(alarmsExempt: false));
      expect(out.length, 1);
      expect(out[0].svcid, 'A');
    });
    test('엣지: 조용시간 자체가 꺼져 있으면 alarmsExempt=false여도 전부 유지', () {
      final out = applyQuietToAlarms(alarms, const QuietConfig(enabled: false, alarmsExempt: false));
      expect(out.length, 2);
    });
  });

  group('직렬화 왕복(백그라운드 저장 경로)', () {
    test('notified 셋 JSON 왕복', () {
      final s = {'new_S1', 'reopen_S2_2026-07-03 20:20'};
      final r = (json.decode(json.encode(s.toList())) as List).map((e) => e.toString()).toSet();
      expect(r, s);
    });
  });
}
