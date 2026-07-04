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
      final out = planInstantNotifications(f, const Subscription(), {});
      expect(out.length, 1);
      expect(out[0].key, 'new_S1');
      expect(out[0].url, contains('yeyak'));
    });

    test('엣지: 이미 알린 키는 재발송 안 함', () {
      final f = feedFrom({
        'courses': [course('S1')],
        'new': [{'id': 'S1', 'name': 'x', 'area': '', 'status': '접수중', 'seen_at': ''}],
      });
      expect(planInstantNotifications(f, const Subscription(), {'new_S1'}), isEmpty);
    });

    test('엣지: 구독조건 불일치 신규는 스킵', () {
      final f = feedFrom({
        'courses': [course('S1', area: '강남구')],
        'new': [{'id': 'S1', 'name': 'x', 'area': '강남구', 'status': '접수중', 'seen_at': ''}],
      });
      expect(planInstantNotifications(f, const Subscription(areas: {'마포구'}), {}), isEmpty);
    });

    test('엣지: courses에 없는 신규(고아) — 조건 없으면 발송, 있으면 보수적 스킵', () {
      final f = feedFrom({
        'new': [{'id': 'S9', 'name': '고아', 'area': '', 'status': '접수중', 'seen_at': ''}],
      });
      expect(planInstantNotifications(f, const Subscription(), {}).length, 1);
      expect(planInstantNotifications(f, const Subscription(freeOnly: true), {}), isEmpty);
    });
  });

  group('즉시 알림(재오픈)', () {
    Map<String, dynamic> reopen(String id, {int inWindow = 1}) =>
        {'id': id, 'name': 'r', 'area': '마포구', 'in_window': inWindow, 'at': '2026-07-03 20:20'};

    test('기본: in_window 재오픈 + 현재 접수중 → 알림', () {
      final f = feedFrom({'courses': [course('S1')], 'reopened': [reopen('S1')]});
      final out = planInstantNotifications(f, const Subscription(), {});
      expect(out.length, 1);
      expect(out[0].key, startsWith('reopen_S1'));
    });

    test('엣지: 접수기간 밖(in_window=0) 재오픈은 스킵', () {
      final f = feedFrom({'courses': [course('S1')], 'reopened': [reopen('S1', inWindow: 0)]});
      expect(planInstantNotifications(f, const Subscription(), {}), isEmpty);
    });

    test('엣지: 재오픈 후 이미 다시 마감된 강좌는 스킵(헛알림 방지)', () {
      final f = feedFrom({'courses': [course('S1', status: '예약마감')], 'reopened': [reopen('S1')]});
      expect(planInstantNotifications(f, const Subscription(), {}), isEmpty);
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

  group('pruneNotified', () {
    test('feed에서 사라진 키 제거, 살아있는 키 유지', () {
      final f = feedFrom({
        'new': [{'id': 'S1', 'name': '', 'area': '', 'status': '', 'seen_at': ''}],
      });
      final pruned = pruneNotified({'new_S1', 'new_GONE', 'reopen_GONE_x'}, f);
      expect(pruned, {'new_S1'});
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
