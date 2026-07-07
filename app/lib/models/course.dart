/// feed.json 모델 — 파이프라인(make_feed.py)의 출력과 1:1.
/// 스키마가 바뀌면 make_feed.py와 이 파일을 같은 커밋에서 고친다(모노레포 이유).
library;

/// 강좌 하나. 필드는 feed의 courses[] 원소와 동일.
class Course {
  final String id;
  final String name;
  final String area; // 빈 문자열 가능(약 1.4%) → UI에서는 areaLabel 사용
  final String cat;
  final String status; // 접수중 | 안내중 | 예약마감
  final String pay; // 무료 | 유료 | 유료(요금안내문의) | ''(레거시)
  final String target;
  final String rcptBgn; // "YYYY-MM-DD HH:MM" 또는 ''
  final String rcptEnd;
  final double? x; // 경도. 좌표 없는 강좌 존재(~2%)
  final double? y; // 위도
  final String url; // yeyak 외 umppa 등 다중 도메인 — 항상 외부 브라우저로 연다
  final String img;

  const Course({
    required this.id,
    required this.name,
    required this.area,
    required this.cat,
    required this.status,
    required this.pay,
    required this.target,
    required this.rcptBgn,
    required this.rcptEnd,
    required this.x,
    required this.y,
    required this.url,
    required this.img,
  });

  /// 빈 area는 서울시 전역 프로그램(주최가 시 직영 등)이라는 뜻.
  String get areaLabel => area.isEmpty ? '서울전역' : area;

  bool get isFree => pay == '무료';
  bool get isOpen => status == '접수중';

  /// 지금 실질적으로 접수 가능한가 — 서버 상태(SVCSTATNM)는 야간 배치로만 갱신되므로
  /// '안내중'이어도 접수기간(RCPTBGNDT~ENDDT)이 시작됐으면 열린 것으로 취급한다
  /// (M4 실기기: 10시 오픈이 지나도 오픈예정 탭에 남아있던 표시 결함의 수정).
  bool effectivelyOpen(DateTime now) {
    if (isOpen) return true;
    if (status != '안내중') return false;
    final bgn = rcptBgnDt;
    if (bgn == null || bgn.isAfter(now)) return false;
    final end = rcptEndDt;
    return end == null || !now.isAfter(end);
  }

  /// 접수 시작이 미래인가 (upcoming 판단은 서버 feed에도 있지만 클라에서도 계산 가능해야 함)
  DateTime? get rcptBgnDt => _parseDt(rcptBgn);
  DateTime? get rcptEndDt => _parseDt(rcptEnd);

  static DateTime? _parseDt(String s) {
    if (s.isEmpty) return null;
    // "YYYY-MM-DD HH:MM" → ISO로 변형해 파싱. 형식 불량은 null(방어).
    return DateTime.tryParse(s.replaceFirst(' ', 'T'));
  }

  static double? _toDouble(dynamic v) {
    if (v == null) return null;
    final s = v.toString().trim();
    if (s.isEmpty) return null;
    return double.tryParse(s);
  }

  factory Course.fromJson(Map<String, dynamic> j) => Course(
        id: (j['id'] ?? '') as String,
        name: (j['name'] ?? '') as String,
        area: (j['area'] ?? '') as String,
        cat: (j['cat'] ?? '') as String,
        status: (j['status'] ?? '') as String,
        pay: (j['pay'] ?? '') as String,
        target: (j['target'] ?? '') as String,
        rcptBgn: (j['rcpt_bgn'] ?? '') as String,
        rcptEnd: (j['rcpt_end'] ?? '') as String,
        x: _toDouble(j['x']),
        y: _toDouble(j['y']),
        url: (j['url'] ?? '') as String,
        img: (j['img'] ?? '') as String,
      );
}

/// 접수 오픈 예정(광클 알람 대상)
class UpcomingOpening {
  final String id;
  final String name;
  final String area;
  final String openAt; // "YYYY-MM-DD HH:MM"
  final int leadMin;

  const UpcomingOpening(
      {required this.id, required this.name, required this.area, required this.openAt, required this.leadMin});

  DateTime? get openAtDt => Course._parseDt(openAt);

  factory UpcomingOpening.fromJson(Map<String, dynamic> j) => UpcomingOpening(
        id: (j['id'] ?? '') as String,
        name: (j['name'] ?? '') as String,
        area: (j['area'] ?? '') as String,
        openAt: (j['open_at'] ?? '') as String,
        leadMin: (j['lead_min'] ?? 0) as int,
      );
}

/// 신규 등록 강좌 이벤트
class NewCourseEvent {
  final String id;
  final String name;
  final String area;
  final String status;
  final String seenAt;

  const NewCourseEvent(
      {required this.id, required this.name, required this.area, required this.status, required this.seenAt});

  factory NewCourseEvent.fromJson(Map<String, dynamic> j) => NewCourseEvent(
        id: (j['id'] ?? '') as String,
        name: (j['name'] ?? '') as String,
        area: (j['area'] ?? '') as String,
        status: (j['status'] ?? '') as String,
        seenAt: (j['seen_at'] ?? '') as String,
      );
}

/// 재오픈(닫힘→접수중) 이벤트
class ReopenEvent {
  final String id;
  final String name;
  final String area;
  final bool inWindow;
  final String at;

  const ReopenEvent(
      {required this.id, required this.name, required this.area, required this.inWindow, required this.at});

  factory ReopenEvent.fromJson(Map<String, dynamic> j) => ReopenEvent(
        id: (j['id'] ?? '') as String,
        name: (j['name'] ?? '') as String,
        area: (j['area'] ?? '') as String,
        inWindow: (j['in_window'] ?? 0) == 1,
        at: (j['at'] ?? '') as String,
      );
}

/// feed.json 전체
class Feed {
  final int version;
  final String generatedAt;
  final List<Course> courses;
  final List<NewCourseEvent> newCourses;
  final List<ReopenEvent> reopened;
  final List<UpcomingOpening> upcoming;

  const Feed({
    required this.version,
    required this.generatedAt,
    required this.courses,
    required this.newCourses,
    required this.reopened,
    required this.upcoming,
  });

  factory Feed.fromJson(Map<String, dynamic> j) {
    final version = (j['version'] ?? 0) as int;
    if (version != 1) {
      // 스키마가 앞서가면 구버전 앱이 조용히 깨지는 것 방지 — 명시적으로 던진다.
      throw FormatException('지원하지 않는 feed version: $version');
    }
    List<T> parseList<T>(String key, T Function(Map<String, dynamic>) f) =>
        ((j[key] ?? []) as List).map((e) => f(e as Map<String, dynamic>)).toList();
    return Feed(
      version: version,
      generatedAt: (j['generated_at'] ?? '') as String,
      courses: parseList('courses', Course.fromJson),
      newCourses: parseList('new', NewCourseEvent.fromJson),
      reopened: parseList('reopened', ReopenEvent.fromJson),
      upcoming: parseList('upcoming', UpcomingOpening.fromJson),
    );
  }
}
