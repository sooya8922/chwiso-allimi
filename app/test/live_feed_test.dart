// 라이브 feed 통합 테스트 — repo 루트의 실제 feed.json(파이프라인이 하루 4회 갱신)을
// 앱 파서로 그대로 파싱한다. make_feed.py와 앱 모델이 어긋나면 여기서 CI가 죽는다.
// (모노레포로 묶은 이유가 이 테스트다)
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yeollim_allim/models/course.dart';

void main() {
  final feedFile = File('../feed.json');

  test('실제 feed.json 전체 파싱 + 데이터 품질 불변식', () {
    if (!feedFile.existsSync()) {
      markTestSkipped('feed.json 없음 (레포 루트 밖에서 실행됨) — 스킵');
      return;
    }
    final feed = Feed.fromJson(json.decode(feedFile.readAsStringSync()) as Map<String, dynamic>);

    // 규모 불변식 (courses가 급감하면 파이프라인 이상)
    expect(feed.courses.length, greaterThan(500), reason: '강좌 수 급감 = 파이프라인 이상 신호');

    // 필드 불변식 — 전 강좌
    for (final c in feed.courses) {
      expect(c.id, isNotEmpty);
      expect(c.name, isNotEmpty);
      expect(const ['접수중', '안내중', '예약마감'].contains(c.status), true, reason: '${c.id}: ${c.status}');
      expect(c.url, startsWith('http'), reason: '${c.id}: url=${c.url}');
      // HTML 엔티티가 새면 make_feed의 clean()이 깨진 것
      expect(c.name.contains('&lt;') || c.name.contains('&#39;'), false, reason: '${c.id}: 엔티티 잔존');
    }

    // upcoming 불변식: 전부 파싱 가능한 미래 시각 + 양수 리드타임
    for (final u in feed.upcoming) {
      expect(u.openAtDt, isNotNull, reason: '${u.id}: open_at=${u.openAt}');
      expect(u.leadMin, greaterThan(0));
    }
  });
}
