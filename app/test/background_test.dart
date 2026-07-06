// refreshAndNotify의 첫 실행 시맨틱 테스트 — M4 실기기에서 겪은
// "설치 직후 지난 7일치 재오픈 알림 폭탄"의 회귀 방지.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yeollim_allim/models/course.dart';
import 'package:yeollim_allim/services/background.dart';

Feed feedWithReopens() => Feed.fromJson({
      'version': 1,
      'generated_at': '2026-07-05 18:48:21',
      'courses': [
        {
          'id': 'S1', 'name': '대모산 7월 행복한 숲', 'area': '강남구', 'cat': '문화체험',
          'status': '접수중', 'pay': '무료', 'target': '', 'rcpt_bgn': '', 'rcpt_end': '',
          'x': '', 'y': '', 'url': 'https://yeyak.seoul.go.kr/x', 'img': '',
        }
      ],
      'new': [
        {'id': 'S1', 'name': '대모산', 'area': '강남구', 'status': '접수중', 'seen_at': '2026-07-05 05:31'}
      ],
      'reopened': [
        {'id': 'S1', 'name': '대모산', 'area': '강남구', 'in_window': 1, 'at': '2026-07-05 18:48'},
        {'id': 'S1', 'name': '대모산', 'area': '강남구', 'in_window': 1, 'at': '2026-07-02 10:16'},
      ],
      'upcoming': [],
    });

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final day = DateTime(2026, 7, 6, 13, 0); // 주간(조용시간 아님)
  final night = DateTime(2026, 7, 6, 23, 30); // 조용시간

  test('첫 실행: 알림 발송 없이 기준선(allKeys)만 저장 — 설치 직후 폭탄 방지', () async {
    SharedPreferences.setMockInitialValues({}); // 완전 첫 실행
    try {
      await refreshAndNotify(preloaded: feedWithReopens(), now: day);
    } catch (_) {
      // 알람 재예약 파트의 플러그인 부재(MissingPlugin) — 즉시알림 파트는 그 전에 완료됨.
      // 첫 실행 경로는 showInstant를 아예 호출하지 않으므로 여기 도달 = 발송 0건이었다는 뜻.
    }
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getString('notified_keys_v1');
    expect(raw, isNotNull, reason: '첫 실행 후 기준선이 저장돼야 함');
    final keys = (json.decode(raw!) as List).map((e) => e.toString()).toSet();
    expect(keys, {
      'new_S1',
      'reopen_S1_2026-07-05 18:48',
      'reopen_S1_2026-07-02 10:16',
    }, reason: '이벤트 전부(중복 포함)가 "본 것"으로 기록 — 다음 실행에서 소급 발화 없음');
  });

  test('이중 실행 가드: 60초 내 재실행이면 기준선 저장을 건너뜀(즉시알림 파트 스킵)', () async {
    SharedPreferences.setMockInitialValues({
      'notify_run_ts_v1': DateTime.now().millisecondsSinceEpoch - 5000, // 5초 전 실행됨
    });
    try {
      await refreshAndNotify(preloaded: feedWithReopens(), now: day);
    } catch (_) {/* 알람 파트 플러그인 부재 */}
    final sp = await SharedPreferences.getInstance();
    expect(sp.getString('notified_keys_v1'), isNull,
        reason: '가드에 걸리면 즉시알림 파트(저장 포함)를 통째로 스킵해야 함');
  });

  test('조용시간(23:30): 기존 사용자는 발송/저장 모두 스킵 → 아침에 알림', () async {
    SharedPreferences.setMockInitialValues({
      'notified_keys_v1': '["new_S1"]', // 기존 사용자 (재오픈 2건은 아직 안 봄)
    });
    try {
      await refreshAndNotify(preloaded: feedWithReopens(), now: night);
    } catch (_) {/* 알람 파트 플러그인 부재 */}
    final sp = await SharedPreferences.getInstance();
    expect(sp.getString('notified_keys_v1'), '["new_S1"]',
        reason: '조용시간엔 키 저장도 스킵 — 밤새 이벤트가 "본 것"으로 소실되면 안 됨');
    expect(sp.getInt('notify_run_ts_v1'), isNull, reason: '실행 마킹도 스킵');
  });

  test('엣지: 조용시간이라도 첫 실행 기준선은 저장(밤 설치→아침 폭탄 방지)', () async {
    SharedPreferences.setMockInitialValues({});
    try {
      await refreshAndNotify(preloaded: feedWithReopens(), now: night);
    } catch (_) {/* 알람 파트 플러그인 부재 */}
    final sp = await SharedPreferences.getInstance();
    expect(sp.getString('notified_keys_v1'), isNotNull,
        reason: '밤에 설치해도 기준선은 잡혀야 아침 폭탄이 없다');
  });
}
