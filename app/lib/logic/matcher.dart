/// 구독조건 매칭 — 순수 함수만. UI/IO 없음(단위테스트 대상).
///
/// 매칭 의미론(결정 사항, 테스트로 고정):
///  - 조건 그룹(지역/무료/대상/키워드)끼리는 AND, 그룹 안의 값끼리는 OR.
///  - 비어있는 그룹 = 전체 허용.
///  - 지역: area가 빈 강좌는 '서울전역' 프로그램 → 어떤 지역 선택에도 매치.
///  - 무료만: pay가 정확히 '무료'인 것만. 레거시 빈 pay는 '모름'이라 제외(보수적).
///  - 대상: target+name 텍스트에 대상군 패턴이 있는지로 판정.
library;

import '../models/course.dart';

/// 사용자 구독조건. shared_preferences에 JSON으로 저장된다.
class Subscription {
  final Set<String> areas; // 예: {'마포구','서대문구'} — 빈 셋=전체
  final bool freeOnly;
  final Set<String> targets; // {'kids','adult','senior'} — 빈 셋=전체
  final List<String> keywords; // 예: ['방학','원예'] — 빈 리스트=전체

  const Subscription({
    this.areas = const {},
    this.freeOnly = false,
    this.targets = const {},
    this.keywords = const [],
  });

  Map<String, dynamic> toJson() => {
        'areas': areas.toList(),
        'freeOnly': freeOnly,
        'targets': targets.toList(),
        'keywords': keywords,
      };

  factory Subscription.fromJson(Map<String, dynamic> j) => Subscription(
        areas: ((j['areas'] ?? []) as List).map((e) => e.toString()).toSet(),
        freeOnly: (j['freeOnly'] ?? false) as bool,
        targets: ((j['targets'] ?? []) as List).map((e) => e.toString()).toSet(),
        keywords: ((j['keywords'] ?? []) as List).map((e) => e.toString()).toList(),
      );

  Subscription copyWith({Set<String>? areas, bool? freeOnly, Set<String>? targets, List<String>? keywords}) =>
      Subscription(
        areas: areas ?? this.areas,
        freeOnly: freeOnly ?? this.freeOnly,
        targets: targets ?? this.targets,
        keywords: keywords ?? this.keywords,
      );

  bool get isEmpty => areas.isEmpty && !freeOnly && targets.isEmpty && keywords.isEmpty;
}

/// 대상군 판별 패턴. USETGTINFO가 자유텍스트라 정규식으로 흡수.
final Map<String, RegExp> _targetPatterns = {
  // '초1-3' 같은 실데이터 표기까지 흡수 (초등 표기 다양: 초등/초1/초 1~3학년)
  'kids': RegExp(r'어린이|유아|아동|초등|초\s*[1-9]|학생|가족|키즈|자녀'),
  'adult': RegExp(r'성인|일반|누구나|시민|직장인'),
  'senior': RegExp(r'노인|어르신|시니어|[456][05]\s*세\s*이상'),
};

/// USETGTINFO의 괄호 속 부가설명을 제거해 '진짜 대상군'만 남긴다.
/// 예) '성인(어르신(만 60세 이상)), 장애인(초등학생 수준 이상)' → '성인, 장애인'
///   ← 이렇게 안 하면 '장애인(초등학생 수준)'의 '초등'을 어린이로 오판(실기기 버그).
/// 중첩 괄호도 안쪽부터 반복 제거.
String stripTargetDetail(String s) {
  var t = s;
  final inner = RegExp(r'\([^()]*\)');
  while (inner.hasMatch(t)) {
    t = t.replaceAll(inner, '');
  }
  return t;
}

bool _matchTarget(Course c, Set<String> targets) {
  if (targets.isEmpty) return true;
  // 대상(target)은 괄호 부가설명 제거 후 매칭. 이름(name)은 대상 표기가 자주 들어가 그대로 사용.
  final text = '${stripTargetDetail(c.target)} ${c.name}';
  return targets.any((t) => _targetPatterns[t]?.hasMatch(text) ?? false);
}

bool _matchArea(Course c, Set<String> areas) {
  if (areas.isEmpty) return true;
  if (c.area.isEmpty) return true; // 서울전역 프로그램은 항상 매치
  return areas.contains(c.area);
}

bool _matchKeywords(Course c, List<String> keywords) {
  // 공백뿐인 키워드는 버린다 — 유효 키워드가 0개면 그룹 비활성(전체 허용).
  // (안 그러면 '  ' 하나 저장된 순간 모든 알림이 조용히 죽는 엣지가 생긴다)
  final effective = keywords.map((k) => k.trim()).where((k) => k.isNotEmpty).toList();
  if (effective.isEmpty) return true;
  final text = '${c.name} ${c.cat} ${c.target}'.toLowerCase();
  return effective.any((k) => text.contains(k.toLowerCase()));
}

/// 강좌 c가 구독조건 s에 걸리는가.
bool matches(Course c, Subscription s) {
  if (s.freeOnly && !c.isFree) return false;
  return _matchArea(c, s.areas) && _matchTarget(c, s.targets) && _matchKeywords(c, s.keywords);
}

/// 리스트 필터링 헬퍼
List<Course> filterCourses(List<Course> all, Subscription s) => all.where((c) => matches(c, s)).toList();
