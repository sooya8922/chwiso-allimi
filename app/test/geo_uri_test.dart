// 지도 URL 순수 함수 테스트 — geo: 스킴이 갤럭시에서 "존재하지 않는 URL" 오류를 내던 문제(실기기 제보)
// 를 카카오맵 웹링크 + 구글맵 폴백으로 교체한 뒤의 회귀 방지.
import 'package:flutter_test/flutter_test.dart';
import 'package:yeollim_allim/widgets/course_card.dart';

void main() {
  group('buildKakaoMapUrl', () {
    test('좌표 순서 name,위도(lat),경도(lng)', () {
      final s = buildKakaoMapUrl(126.9, 37.5, '강좌');
      expect(s, endsWith(',37.5,126.9'));
      expect(s, startsWith('https://map.kakao.com/link/map/'));
    });

    test('이름의 쉼표가 인코딩되어 링크 구분자와 충돌 안 함', () {
      // 쉼표가 살아있으면 kakao가 좌표 파싱을 망침 → %2C로 인코딩돼야
      final s = buildKakaoMapUrl(126.9, 37.5, '요리, 공예 교실');
      // 구분용 쉼표는 정확히 2개(위도 앞, 경도 앞)만 남아야
      expect(','.allMatches(s).length, 2);
      expect(s.contains('%2C'), true);
      expect(() => Uri.parse(s), returnsNormally);
    });

    test('괄호·공백·슬래시 포함 이름도 유효한 URL', () {
      final s = buildKakaoMapUrl(127.0, 37.6, '텃밭 생태체험 (잠실/한강)');
      expect(() => Uri.parse(s), returnsNormally);
      expect(s.contains(' '), false); // 공백 인코딩
    });
  });

  group('buildGoogleMapUrl', () {
    test('범용 검색 URL 형식', () {
      final s = buildGoogleMapUrl(126.9, 37.5);
      expect(s, 'https://www.google.com/maps/search/?api=1&query=37.5,126.9');
      expect(() => Uri.parse(s), returnsNormally);
    });
  });
}
