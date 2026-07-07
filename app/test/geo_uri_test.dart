// buildGeoUri 순수 함수 테스트 — 강좌명의 괄호가 geo 라벨을 깨뜨리지 않는지(MAJOR-1 회귀).
import 'package:flutter_test/flutter_test.dart';
import 'package:yeollim_allim/widgets/course_card.dart';

void main() {
  group('buildGeoUri', () {
    test('좌표가 올바른 순서(위도,경도)로 들어감', () {
      final s = buildGeoUri(126.9, 37.5, '강좌');
      expect(s, startsWith('geo:37.5,126.9?q=37.5,126.9('));
    });

    test('괄호 포함 이름(강좌 63%) — () 가 인코딩되어 라벨 구분자와 충돌 안 함', () {
      final s = buildGeoUri(126.9, 37.5, '텃밭 생태체험 (잠실한강)');
      // 원시 ( ) 는 라벨을 감싸는 딱 한 쌍만 존재해야 함
      expect('('.allMatches(s).length, 1);
      expect(')'.allMatches(s).length, 1);
      expect(s.contains('%28'), true); // 이름 속 ( 는 인코딩됨
      expect(s.contains('%29'), true);
      // Uri.parse가 예외 없이 성공해야 함
      expect(() => Uri.parse(s), returnsNormally);
    });

    test('중첩 괄호 이름도 안전', () {
      final s = buildGeoUri(127.0, 37.6, '교육 (초등 (3~6학년))');
      expect('('.allMatches(s).length, 1);
      expect(')'.allMatches(s).length, 1);
      expect(() => Uri.parse(s), returnsNormally);
    });

    test('공백·특수문자 인코딩', () {
      final s = buildGeoUri(126.9, 37.5, 'AI & 코딩');
      expect(s.contains(' '), false); // 공백은 %20
      expect(() => Uri.parse(s), returnsNormally);
    });
  });
}
