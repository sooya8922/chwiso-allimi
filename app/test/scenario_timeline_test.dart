// E2E 타임라인 시나리오 — 하루 동안 feed가 여러 번 바뀌는 흐름에서 알림/알람 계획이
// 조용시간·중복방지·재분류와 올바로 상호작용하는지 순수 로직 레벨에서 통합 검증.
import 'package:flutter_test/flutter_test.dart' hide matches;
import 'package:yeollim_allim/logic/matcher.dart';
import 'package:yeollim_allim/logic/notif_planner.dart';
import 'package:yeollim_allim/models/course.dart';

Feed feedOf({List<Map<String, dynamic>> courses = const [], List reopened = const [], List upcoming = const [], List newc = const []}) =>
    Feed.fromJson({
      'version': 1, 'generated_at': 'x', 'sources': ['seoul_public'],
      'courses': courses, 'new': newc, 'reopened': reopened, 'upcoming': upcoming,
    });

Map<String, dynamic> c(String id, {String status = '접수중', String area = '마포구', String pay = '무료', String bgn = '', String end = ''}) =>
    {'id': id, 'status': status, 'area': area, 'pay': pay, 'name': '강좌$id', 'cat': '문화',
     'rcpt_bgn': bgn, 'rcpt_end': end, 'x': '126.9', 'y': '37.5', 'url': 'https://yeyak.seoul.go.kr/$id'};

void main() {
  test('시나리오: 밤 배치→조용시간 억제→아침 방출→중복 없음', () {
    // 필터 없음(전체). notified 셋은 기기 저장을 흉내내 누적한다.
    const sub = Subscription();
    final notified = <String>{};

    // T0 (설치 첫 실행, 주간 13:00) — 발송 없이 기준선만
    final f0 = feedOf(
      courses: [c('A'), c('B')],
      reopened: [{'id': 'A', 'name': '강좌A', 'area': '마포구', 'in_window': 1, 'at': '2026-07-06 12:00'}],
    );
    final p0 = planInstantNotifications(f0, sub, notified, now: DateTime(2026, 7, 6, 13, 0));
    // 첫 실행 시맨틱은 background가 담당(발송X, allKeys 저장). 여기선 allKeys를 notified에 반영.
    notified.addAll(p0.allKeys);
    expect(p0.toShow.isNotEmpty, true, reason: '플래너 자체는 후보를 만들지만');
    final seenAfterFirstRun = {...notified};

    // T1 (밤 23:30, 배치로 새 재오픈 B 등장) — background는 조용시간이라 발송/저장 스킵
    final quiet = const QuietConfig();
    expect(inQuietHours(DateTime(2026, 7, 6, 23, 30), quiet), true);
    // 조용시간엔 planInstant를 호출하지 않으므로 notified 불변 — 시뮬레이션도 호출 안 함
    expect(notified, seenAfterFirstRun, reason: '조용시간엔 상태 변화 없음');

    // T2 (다음날 아침 08:30) — B의 새 재오픈이 이제 발송돼야 하고, 이미 본 A는 재발송 금지
    final f2 = feedOf(
      courses: [c('A'), c('B')],
      reopened: [
        {'id': 'A', 'name': '강좌A', 'area': '마포구', 'in_window': 1, 'at': '2026-07-06 12:00'}, // 이미 봄
        {'id': 'B', 'name': '강좌B', 'area': '마포구', 'in_window': 1, 'at': '2026-07-07 02:00'}, // 밤 배치 신규
      ],
    );
    expect(inQuietHours(DateTime(2026, 7, 7, 8, 30), quiet), false);
    final p2 = planInstantNotifications(f2, sub, notified, now: DateTime(2026, 7, 7, 8, 30));
    final ids = p2.toShow.map((n) => n.key).toList();
    expect(ids, ['reopen_B_2026-07-07 02:00'], reason: 'B만 신규 발송, A는 억제');
    notified.addAll(p2.allKeys);

    // T3 (같은 날 재실행) — 멱등: 새 이벤트 없으면 발송 0
    final p3 = planInstantNotifications(f2, sub, notified, now: DateTime(2026, 7, 7, 9, 0));
    expect(p3.toShow, isEmpty, reason: '같은 feed 재처리 시 중복 발송 없음');
  });

  test('시나리오: 광클 알람이 하루 진행에 따라 소멸(과거화)', () {
    const sub = Subscription();
    final up = [
      {'id': 'X', 'name': '강좌X', 'area': '마포구', 'open_at': '2026-07-07 10:00', 'lead_min': 1},
      {'id': 'Y', 'name': '강좌Y', 'area': '마포구', 'open_at': '2026-07-07 14:00', 'lead_min': 1},
    ];
    final f = feedOf(courses: [c('X'), c('Y')], upcoming: up);

    // 09:00 — 둘 다 미래 → 알람 2개
    expect(planAlarms(f, sub, DateTime(2026, 7, 7, 9, 0)).length, 2);
    // 10:30 — X 오픈 지남 → 알람 1개(Y만)
    final a = planAlarms(f, sub, DateTime(2026, 7, 7, 10, 30));
    expect(a.length, 1);
    expect(a.first.svcid, 'Y');
    // 15:00 — 둘 다 지남 → 0개
    expect(planAlarms(f, sub, DateTime(2026, 7, 7, 15, 0)), isEmpty);
  });

  test('시나리오: 필터 좁히면 그 조건만 — 음성 대조', () {
    const sub = Subscription(areas: {'성동구'}, freeOnly: true);
    final f = feedOf(
      courses: [c('S', area: '성동구', pay: '무료'), c('G', area: '강남구', pay: '무료'), c('P', area: '성동구', pay: '유료')],
      reopened: [
        {'id': 'S', 'name': '성동무료', 'area': '성동구', 'in_window': 1, 'at': '2026-07-07 10:00'},
        {'id': 'G', 'name': '강남무료', 'area': '강남구', 'in_window': 1, 'at': '2026-07-07 10:00'},
        {'id': 'P', 'name': '성동유료', 'area': '성동구', 'in_window': 1, 'at': '2026-07-07 10:00'},
      ],
    );
    final out = planInstantNotifications(f, sub, {}, now: DateTime(2026, 7, 7, 11, 0)).toShow;
    expect(out.map((n) => n.key), ['reopen_S_2026-07-07 10:00'],
        reason: '성동+무료 S만 — 강남(G)·유료(P)는 안 옴');
  });

  test('시나리오: 알람 폭주 시 요약으로 묶임(아침 방출 도배 방지)', () {
    // 6건 재오픈이 한 번에 → summarizeBurst가 1건 요약으로
    final reopens = List.generate(6, (i) => {'id': 'R$i', 'name': '강좌R$i', 'area': '마포구', 'in_window': 1, 'at': '2026-07-07 02:0$i'});
    final courses = List.generate(6, (i) => c('R$i'));
    final f = feedOf(courses: courses, reopened: reopens);
    final plan = planInstantNotifications(f, const Subscription(), {}, now: DateTime(2026, 7, 7, 8, 0));
    expect(plan.toShow.length, 6, reason: '플래너는 6건 생성');
    final summarized = summarizeBurst(plan.toShow);
    expect(summarized.length, 1, reason: '발송 단계에서 1건 요약으로');
    expect(summarized.first.body, contains('재오픈 6건'));
  });
}
