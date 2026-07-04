import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:yeollim_allim/models/course.dart';

/// make_feed.py 출력 형태 그대로의 샘플(실측 라이브 feed에서 발췌·축약).
const sampleFeed = '''
{
  "version": 1,
  "generated_at": "2026-07-04 13:06:43",
  "counts": {"courses": 3, "new": 1, "reopened": 1, "upcoming": 1},
  "courses": [
    {"id":"S1","name":"[월드컵공원] 꽁지 불빛 반딧불이 해설(7월)","area":"마포구","cat":"자연/과학",
     "status":"접수중","pay":"무료","target":" 어린이(가족)","rcpt_bgn":"2026-06-25 10:00",
     "rcpt_end":"2026-07-20 18:00","x":"126.87948","y":"37.57006",
     "url":"https://yeyak.seoul.go.kr/web/reservation/selectReservView.do?rsv_svc_id=S1","img":"https://x/i.jpg"},
    {"id":"S2","name":"성동 가드닝 프로그램-7월","area":"","cat":"문화체험",
     "status":"안내중","pay":"","target":"","rcpt_bgn":"2026-07-06 10:00",
     "rcpt_end":"","x":"","y":"","url":"https://umppa.seoul.go.kr/some/path","img":""},
    {"id":"S3","name":"뜨개모자 뜨기 (중급)","area":"송파구","cat":"문화체험",
     "status":"예약마감","pay":"유료(요금안내문의)","target":"성인","rcpt_bgn":"2026-06-01 09:00",
     "rcpt_end":"2026-07-30 18:00","x":"127.1","y":"37.5",
     "url":"https://yeyak.seoul.go.kr/x","img":""}
  ],
  "new": [{"id":"S2","name":"성동 가드닝 프로그램-7월","area":"","status":"안내중","seen_at":"2026-07-04 13:04"}],
  "reopened": [{"id":"S1","name":"[월드컵공원] 꽁지 불빛 반딧불이 해설(7월)","area":"마포구","in_window":1,"at":"2026-07-03 20:20"}],
  "upcoming": [{"id":"S2","name":"성동 가드닝 프로그램-7월","area":"","open_at":"2026-07-06 10:00","lead_min":2636}]
}
''';

void main() {
  group('Feed 파싱', () {
    final feed = Feed.fromJson(json.decode(sampleFeed) as Map<String, dynamic>);

    test('기본 구조', () {
      expect(feed.version, 1);
      expect(feed.courses.length, 3);
      expect(feed.newCourses.length, 1);
      expect(feed.reopened.length, 1);
      expect(feed.upcoming.length, 1);
    });

    test('정상 강좌 필드', () {
      final c = feed.courses[0];
      expect(c.id, 'S1');
      expect(c.areaLabel, '마포구');
      expect(c.isFree, true);
      expect(c.isOpen, true);
      expect(c.x, closeTo(126.87948, 1e-9));
      expect(c.rcptBgnDt, DateTime(2026, 6, 25, 10, 0));
    });

    test('엣지: 빈 area → 서울전역, 빈 좌표 → null, 빈 rcpt_end → null', () {
      final c = feed.courses[1];
      expect(c.areaLabel, '서울전역');
      expect(c.x, isNull);
      expect(c.y, isNull);
      expect(c.rcptEndDt, isNull);
      expect(c.isFree, false, reason: '레거시 빈 pay는 무료로 오인하면 안 됨');
    });

    test('엣지: 다중 도메인 url 그대로 보존(umppa)', () {
      expect(feed.courses[1].url, startsWith('https://umppa.seoul.go.kr'));
    });

    test('엣지: 유료(요금안내문의)는 무료 아님', () {
      expect(feed.courses[2].isFree, false);
    });

    test('reopened.in_window int→bool 변환', () {
      expect(feed.reopened[0].inWindow, true);
    });

    test('upcoming 파싱 + 시각', () {
      final u = feed.upcoming[0];
      expect(u.leadMin, 2636);
      expect(u.openAtDt, DateTime(2026, 7, 6, 10, 0));
    });
  });

  group('Feed 방어', () {
    test('엣지: 미래 스키마 버전 → 명시적 예외', () {
      expect(() => Feed.fromJson(const {'version': 2}), throwsFormatException);
    });

    test('엣지: 리스트 필드 누락 → 빈 리스트(크래시 없음)', () {
      final f = Feed.fromJson(const {'version': 1, 'generated_at': 'x'});
      expect(f.courses, isEmpty);
      expect(f.upcoming, isEmpty);
    });

    test('엣지: 형식 불량 일시 → null(크래시 없음)', () {
      final c = Course.fromJson(const {'id': 'S9', 'rcpt_bgn': '이상한값'});
      expect(c.rcptBgnDt, isNull);
    });
  });
}
