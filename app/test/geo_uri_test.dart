// 지도 URL 후보 목록 테스트 — 카카오맵→네이버맵→구글지도 우선순위 + 각 URL 형식.
// 앱 스킴은 canLaunchUrl로 설치 판정 후 실행되므로 오류 화면 없이 조용히 폴백된다(실기기 제보 반영).
import 'package:flutter_test/flutter_test.dart';
import 'package:yeollim_allim/widgets/course_card.dart';

void main() {
  group('buildMapCandidates', () {
    final c = buildMapCandidates(126.9, 37.5); // lng, lat

    test('우선순위: 카카오 → 네이버 → 구글(3개)', () {
      expect(c.length, 3);
      expect(c[0], startsWith('kakaomap://'));
      expect(c[1], startsWith('nmap://'));
      expect(c[2], startsWith('https://www.google.com/maps'));
    });

    test('카카오맵: 위도,경도 순', () {
      expect(c[0], 'kakaomap://look?p=37.5,126.9');
    });

    test('네이버지도: lat/lng 파라미터', () {
      expect(c[1], contains('lat=37.5'));
      expect(c[1], contains('lng=126.9'));
    });

    test('구글지도 웹: 최종 폴백(항상 열림)', () {
      expect(c[2], 'https://www.google.com/maps/search/?api=1&query=37.5,126.9');
    });

    test('모든 후보가 파싱 가능한 유효 URI', () {
      for (final u in c) {
        expect(() => Uri.parse(u), returnsNormally, reason: u);
      }
    });

    test('좌표만 사용 → 이름 특수문자로 깨질 여지 없음(문제였던 실좌표로도)', () {
      final r = buildMapCandidates(127.05775790548498, 37.55734277961993);
      for (final u in r) {
        expect(() => Uri.parse(u), returnsNormally);
      }
    });
  });
}
