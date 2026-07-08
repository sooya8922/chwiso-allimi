// flutter_test의 내장 matcher `matches(Pattern)`와 우리 `matches(Course, Subscription)` 충돌 → hide
import 'package:flutter_test/flutter_test.dart' hide matches;
import 'package:yeollim_allim/logic/matcher.dart';
import 'package:yeollim_allim/models/course.dart';

Course mk({
  String area = '마포구',
  String pay = '무료',
  String target = '성인',
  String name = '테스트 강좌',
  String cat = '문화체험',
  String status = '접수중',
}) =>
    Course(
      id: 'S1',
      name: name,
      area: area,
      cat: cat,
      status: status,
      pay: pay,
      target: target,
      rcptBgn: '2026-07-10 10:00',
      rcptEnd: '2026-07-20 18:00',
      x: 126.9,
      y: 37.5,
      url: 'https://yeyak.seoul.go.kr/x',
      img: '',
    );

void main() {
  group('빈 구독조건(기본값)', () {
    test('모든 강좌 매치', () {
      expect(matches(mk(), const Subscription()), true);
      expect(matches(mk(area: '', pay: '', target: ''), const Subscription()), true);
    });
  });

  group('지역 필터', () {
    const s = Subscription(areas: {'마포구', '서대문구'});
    test('선택 구 매치', () => expect(matches(mk(area: '마포구'), s), true));
    test('미선택 구 제외', () => expect(matches(mk(area: '강남구'), s), false));
    test('엣지: 빈 area(서울전역)는 어떤 지역 선택에도 매치', () => expect(matches(mk(area: ''), s), true));
  });

  group('무료 필터', () {
    const s = Subscription(freeOnly: true);
    test('무료 매치', () => expect(matches(mk(pay: '무료'), s), true));
    test('유료 제외', () => expect(matches(mk(pay: '유료'), s), false));
    test('엣지: 유료(요금안내문의) 제외', () => expect(matches(mk(pay: '유료(요금안내문의)'), s), false));
    test('엣지: 레거시 빈 pay는 모름→보수적으로 제외', () => expect(matches(mk(pay: ''), s), false));
  });

  group('대상 필터', () {
    test('kids: 어린이/가족/초등 흡수', () {
      const s = Subscription(targets: {'kids'});
      expect(matches(mk(target: ' 어린이(내 친구 박물관)'), s), true);
      expect(matches(mk(target: '7세 이상 가족'), s), true);
      expect(matches(mk(target: '', name: '[방학특강/ 초1-3] 라임 썸머스쿨'), s), true, reason: 'target 비어도 name에서 흡수');
      expect(matches(mk(target: '성인'), s), false);
    });
    test('senior: 실측 표현 흡수 (실데이터는 대부분 최상위에 "어르신")', () {
      const s = Subscription(targets: {'senior'});
      expect(matches(mk(target: '성인, 어르신'), s), true); // 실 형식: 최상위 어르신
      expect(matches(mk(target: '어르신'), s), true);
      expect(matches(mk(target: '65세 이상'), s), true); // 괄호 밖 나이 표기
      expect(matches(mk(target: '어린이'), s), false);
    });
    test('복수 대상 = OR', () {
      const s = Subscription(targets: {'kids', 'senior'});
      expect(matches(mk(target: '어린이'), s), true);
      expect(matches(mk(target: '65세 이상'), s), true);
    });

    test('실기기 버그: 어르신/장애인 강좌가 어린이 필터에 오매칭되면 안 됨', () {
      // 실 데이터: target 부가설명 '장애인(초등학생 수준 이상)'의 "초등"이 어린이로 오판되던 케이스
      const kids = Subscription(targets: {'kids'});
      final senior = mk(
        target: '성인(어르신(만 60세 이상)), 장애인(초등학생 수준 이상)',
        name: '[현장/단체/어르신/장애인]신통방통 하수와 만나다!',
      );
      expect(matches(senior, kids), false, reason: '괄호 속 초등학생 수준=난이도, 대상 아님');
      // 반면 진짜 학생 대상은 여전히 매칭
      final student = mk(
        target: '청소년(중고등학생 학급 단체), 초등학생(초4~6학년 학급 단체)',
        name: '[현장&비대면/단체/초4.중.고등] 나도 수질연구사!',
      );
      expect(matches(student, kids), true, reason: '최상위 대상 초등학생 → 어린이 매칭');
      // 어르신 필터로는 신통방통이 잡혀야 함
      expect(matches(senior, const Subscription(targets: {'senior'})), true);
    });

    test('stripTargetDetail: 중첩 괄호 제거', () {
      expect(stripTargetDetail('성인(어르신(만 60세 이상)), 장애인(초등학생 수준 이상)'), '성인, 장애인');
      expect(stripTargetDetail('초등학생(초4~6학년)'), '초등학생');
      expect(stripTargetDetail('성인'), '성인');
      expect(stripTargetDetail(''), '');
    });
  });

  group('키워드 필터', () {
    test('name/cat/target에서 대소문자 무시 매치', () {
      const s = Subscription(keywords: ['원예', 'ai']);
      expect(matches(mk(name: '힐링원예교실'), s), true);
      expect(matches(mk(name: 'AI 하우스 만들기'), s), true);
      expect(matches(mk(name: '목공 체험'), s), false);
    });
    test('엣지: 공백 키워드는 무시(전체를 매치시키면 안 됨)', () {
      const s = Subscription(keywords: ['  ']);
      // 공백뿐인 키워드만 있으면 매치 기준 자체가 없어야 하는데,
      // 현재 의미론: 유효 키워드 0개 취급 → keywords 그룹은 비활성이 아니라 '아무것도 매치 안 함'?
      // 결정: 유효 키워드가 하나도 없으면 그룹 비활성(전체 허용)과 동일하게 동작해야 자연스럽다.
      expect(matches(mk(name: '아무 강좌'), s), true);
    });
  });

  group('그룹 간 AND', () {
    test('지역✓ + 무료✗ = 제외', () {
      const s = Subscription(areas: {'마포구'}, freeOnly: true);
      expect(matches(mk(area: '마포구', pay: '유료'), s), false);
    });
    test('전부 만족 = 매치', () {
      const s = Subscription(areas: {'마포구'}, freeOnly: true, targets: {'kids'}, keywords: ['체험']);
      expect(matches(mk(area: '마포구', pay: '무료', target: '어린이', name: '곤충 체험'), s), true);
    });
  });

  group('Subscription 직렬화 왕복', () {
    test('toJson→fromJson 불변', () {
      const s = Subscription(areas: {'마포구'}, freeOnly: true, targets: {'kids'}, keywords: ['방학']);
      final r = Subscription.fromJson(s.toJson());
      expect(r.areas, s.areas);
      expect(r.freeOnly, s.freeOnly);
      expect(r.targets, s.targets);
      expect(r.keywords, s.keywords);
    });
    test('엣지: 파손 JSON 필드 → 기본값', () {
      final r = Subscription.fromJson(const {});
      expect(r.isEmpty, true);
    });
  });
}
