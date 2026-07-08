// 지도 URL 순수 함수 테스트 — geo:/카카오앱링크가 특정 폰·강좌에서 오류 나던 문제(실기기 반복 제보)
// 를 구글지도 범용 URL(좌표만, 이름 미포함)로 교체한 뒤의 회귀 방지.
import 'package:flutter_test/flutter_test.dart';
import 'package:yeollim_allim/widgets/course_card.dart';

void main() {
  group('buildMapUrl', () {
    test('구글지도 범용 검색 URL 형식(위도,경도)', () {
      final s = buildMapUrl(126.9, 37.5); // lng, lat
      expect(s, 'https://www.google.com/maps/search/?api=1&query=37.5,126.9');
      expect(() => Uri.parse(s), returnsNormally);
    });

    test('이름을 안 쓰므로 어떤 좌표에도 URL이 안 깨짐', () {
      // 문제였던 실 강좌 좌표(성동 하수처리장)로도 유효
      final s = buildMapUrl(127.05775790548498, 37.55734277961993);
      expect(() => Uri.parse(s), returnsNormally);
      expect(s.contains('37.55734277961993'), true);
      expect(s.contains('127.05775790548498'), true);
    });
  });
}
