/// 알림 "계획" — 순수 함수만(플러그인/IO 없음, 단위테스트 대상).
///
/// 두 종류의 알림을 계획한다:
///  1) 즉시 알림: 구독조건에 맞는 신규 등록/재오픈 — 중복 발송 방지(notified 셋)
///  2) 광클 알람: 구독조건에 맞는 접수 오픈예정 — 오픈 10분 전 정확 알람
library;

import '../models/course.dart';
import 'matcher.dart';

/// 광클 알람 리드타임(오픈 몇 분 전에 울릴지)
const alarmLeadMin = 10;

/// Android 정확알람 남발 방지 상한(가까운 순으로 자른다)
const maxScheduledAlarms = 50;

/// 즉시 알림 하나
class PlannedNotification {
  final String key; // 중복 방지 키 (예: "new_S123", "reopen_S123_2026-07-03 20:20")
  final String title;
  final String body;
  final String url; // 탭 시 열 딥링크 (빈 문자열 가능)

  const PlannedNotification({required this.key, required this.title, required this.body, required this.url});
}

/// 예약 알람 하나
class PlannedAlarm {
  final int id; // 플랫폼 알람 id (svcid에서 안정적으로 파생 — 재예약 시 같은 id로 덮어씀)
  final String svcid;
  final DateTime at;
  final String title;
  final String body;
  final String url;

  const PlannedAlarm(
      {required this.id, required this.svcid, required this.at, required this.title, required this.body, required this.url});
}

/// 현재 KST 월클럭(naive) — 기기 TZ가 한국이 아니어도(해외여행 엣지) 데이터(KST)와 일관되게 비교.
///
/// 반드시 isUtc=false(naive)로 반환해야 한다. toUtc().add(9h)를 그대로 반환하면
/// isUtc=true 깃발이 남아 naive로 파싱된 feed 시각과의 비교(epoch 기반)가 9시간 틀어진다
/// — 오픈 9시간 이내 알람이 전부 삭제되고 9시간 경계의 알람이 즉시 발화하던
/// M4 실기기 대참사(7/6 08:50 미발화, 7/7 05:59 조기발화)의 근본 원인.
DateTime kstNow() {
  final u = DateTime.now().toUtc().add(const Duration(hours: 9));
  return DateTime(u.year, u.month, u.day, u.hour, u.minute, u.second);
}

/// 조용시간 설정 — 사용자가 지정(기본 22시~8시). 즉시알림(신규/재오픈)은 이 시간대에
/// 발송하지 않고 다음 주간 확인 때로 미룬다(배치성 소식이라 늦어도 손해 없음 — M4 피드백).
/// [alarmsExempt]=true(기본)면 ⏰ 광클 알람은 예외(자정 오픈을 잡으려고 건 알람은 울리는 게 목적),
/// false면 알람도 조용시간에 걸리는 건 예약하지 않는다.
class QuietConfig {
  final bool enabled;
  final int startHour; // 0~23
  final int endHour; // 0~23 (start>end면 자정 걸침)
  final bool alarmsExempt;

  const QuietConfig({this.enabled = true, this.startHour = 22, this.endHour = 8, this.alarmsExempt = true});

  Map<String, dynamic> toJson() =>
      {'enabled': enabled, 'startHour': startHour, 'endHour': endHour, 'alarmsExempt': alarmsExempt};

  factory QuietConfig.fromJson(Map<String, dynamic> j) => QuietConfig(
        enabled: (j['enabled'] ?? true) as bool,
        startHour: ((j['startHour'] ?? 22) as int).clamp(0, 23),
        endHour: ((j['endHour'] ?? 8) as int).clamp(0, 23),
        alarmsExempt: (j['alarmsExempt'] ?? true) as bool,
      );

  QuietConfig copyWith({bool? enabled, int? startHour, int? endHour, bool? alarmsExempt}) => QuietConfig(
        enabled: enabled ?? this.enabled,
        startHour: startHour ?? this.startHour,
        endHour: endHour ?? this.endHour,
        alarmsExempt: alarmsExempt ?? this.alarmsExempt,
      );
}

/// 지금이 조용시간인가. 자정 걸침(22→8)과 안 걸침(13→18) 모두 지원.
/// 엣지: start==end는 빈 창(조용시간 없음)으로 정의.
bool inQuietHours(DateTime now, [QuietConfig cfg = const QuietConfig()]) {
  if (!cfg.enabled || cfg.startHour == cfg.endHour) return false;
  final h = now.hour;
  return cfg.startHour < cfg.endHour
      ? (h >= cfg.startHour && h < cfg.endHour)
      : (h >= cfg.startHour || h < cfg.endHour);
}

/// 즉시알림이 한 번에 [threshold]건을 넘으면 요약 1건으로 묶는다 —
/// 필터 없이 쓰는 사용자가 아침마다 수십 건 도배당하는 것 방지(M4 실기기 피드백).
/// 개별 키 마킹은 호출측의 allKeys 저장이 담당하므로 여기선 표시만 바꾼다.
List<PlannedNotification> summarizeBurst(List<PlannedNotification> toShow, {int threshold = 5}) {
  if (toShow.length <= threshold) return toShow;
  final reopens = toShow.where((n) => n.key.startsWith('reopen_')).length;
  final news = toShow.length - reopens;
  final parts = <String>[
    if (news > 0) '🆕 새 강좌 $news건',
    if (reopens > 0) '🔓 재오픈 $reopens건',
  ];
  return [
    PlannedNotification(
      key: 'burst_summary',
      title: '🔔 새 소식 ${toShow.length}건',
      body: '${parts.join(' · ')} — 눌러서 확인하세요',
      url: '', // 탭하면 앱이 열린다(딥링크 없음)
    ),
  ];
}

/// 알람 목록에 조용시간 정책 적용 — alarmsExempt면 그대로, 아니면 조용시간에
/// 울릴 알람 제거(미루면 접수 시작을 지나버려 의미가 없으므로 제거가 정직하다).
List<PlannedAlarm> applyQuietToAlarms(List<PlannedAlarm> alarms, QuietConfig cfg) {
  if (cfg.alarmsExempt) return alarms;
  return alarms.where((a) => !inQuietHours(a.at, cfg)).toList();
}

/// 오픈까지 남은 시간 라벨 — 반드시 '지금' 기준으로 계산(feed의 lead_min은 생성시점 기준이라
/// 그대로 쓰면 "09시 시작인데 3시간 후" 같은 어긋남이 생긴다 — M4 실기기 실측 버그).
String leadLabel(DateTime? openAt, DateTime now) {
  if (openAt == null) return '';
  final min = openAt.difference(now).inMinutes;
  if (min <= 0) return '오픈!';
  if (min < 60) return '$min분 후';
  if (min < 1440) return '${(min / 60).round()}시간 후';
  return '${(min / 1440).round()}일 후';
}

/// svcid → 안정적 32비트 양수 id (dart String.hashCode는 실행마다 달라질 수 있어 직접 FNV-1a)
int stableId(String svcid) {
  var h = 0x811c9dc5;
  for (final c in svcid.codeUnits) {
    h ^= c;
    h = (h * 0x01000193) & 0x7fffffff;
  }
  return h & 0x7fffffff; // 빈 문자열이면 루프 미실행 → 시드가 31비트 초과(음수화) → 반환 시 마스킹
}

/// 즉시 알림 계획 결과.
/// [toShow]: 지금 발송할 알림. [allKeys]: 이번 feed의 모든 이벤트 키 —
/// 발송 여부와 무관하게 전부 '본 것'으로 저장해야 한다(조건 변경/상태 변화가
/// 과거 이벤트를 소급 발화시키는 엣지 방지).
class InstantPlan {
  final List<PlannedNotification> toShow;
  final Set<String> allKeys;

  const InstantPlan({required this.toShow, required this.allKeys});
}

/// 1) 신규/재오픈 즉시 알림 계획.
/// [notified]: 이미 본 키 셋 — 여기 있는 건 다시 안 보낸다(호출측이 저장/로드).
///
/// 중복 방지 3중(M4 실기기에서 발견된 알림 폭탄/중복의 수정):
///  a. 강좌당 최신 재오픈 이벤트 1건만 (같은 강좌가 7일 윈도우에 2~3회 재오픈하는 게 실측 32/121)
///  b. 쿨다운: 이 강좌의 다른 재오픈 이벤트를 이미 알렸으면(그 이벤트가 아직 feed에 있는 동안) 억제
///  c. 첫 실행은 호출측이 allKeys만 저장하고 발송 안 함(설치 직후 지난 7일치 폭탄 방지)
InstantPlan planInstantNotifications(Feed feed, Subscription sub, Set<String> notified, {DateTime? now}) {
  final nowKst = now ?? kstNow();
  final byId = {for (final c in feed.courses) c.id: c};
  final out = <PlannedNotification>[];
  final allKeys = <String>{
    ...feed.newCourses.map((n) => 'new_${n.id}'),
    ...feed.reopened.map((r) => 'reopen_${r.id}_${r.at}'),
  };

  for (final n in feed.newCourses) {
    final key = 'new_${n.id}';
    if (notified.contains(key)) continue;
    final c = byId[n.id];
    if (c != null && !matches(c, sub)) continue; // 강좌 상세를 알면 조건 필터
    if (c == null && !sub.isEmpty) continue; // 상세 모르는데 조건이 있으면 보수적으로 스킵
    out.add(PlannedNotification(
      key: key,
      title: '🆕 새 강좌 열림',
      body: '[${n.area.isEmpty ? '서울전역' : n.area}] ${n.name}',
      url: c?.url ?? '',
    ));
  }

  // 재오픈: 강좌별로 묶어 최신 이벤트 1건만 평가 (a)
  final latestByCourse = <String, ReopenEvent>{};
  for (final r in feed.reopened) {
    final cur = latestByCourse[r.id];
    if (cur == null || r.at.compareTo(cur.at) > 0) latestByCourse[r.id] = r;
  }
  for (final r in latestByCourse.values) {
    if (!r.inWindow) continue; // 접수기간 밖 재오픈은 신청 불가 → 알림 가치 없음
    final key = 'reopen_${r.id}_${r.at}';
    if (notified.contains(key)) continue;
    // 쿨다운 (b): 같은 강좌의 다른 재오픈을 이미 알렸으면 억제
    if (notified.any((k) => k.startsWith('reopen_${r.id}_'))) continue;
    final c = byId[r.id];
    if (c != null && !matches(c, sub)) continue;
    if (c == null && !sub.isEmpty) continue;
    // 지금 실질적으로 열려있는 것만 (재오픈 후 다시 마감=헛알림). '안내중+접수기간내'도 열린 것으로
    // 취급해야 UI(접수중 탭)와 알림이 어긋나지 않음 — isOpen(엄격) 대신 effectivelyOpen.
    if (c != null && !c.effectivelyOpen(nowKst)) continue;
    out.add(PlannedNotification(
      key: key,
      title: '🔓 마감됐던 강좌가 다시 열렸어요',
      body: '[${r.area.isEmpty ? '서울전역' : r.area}] ${r.name}',
      url: c?.url ?? '',
    ));
  }
  return InstantPlan(toShow: out, allKeys: allKeys);
}

/// 2) 광클 알람 계획. 반환은 시각 오름차순, 상한 [maxScheduledAlarms]개.
///  - 오픈이 이미 지난 것 제외
///  - 오픈까지 10분 미만이면 즉시(now+15초) 울리도록 보정 (아예 안 울리는 것보다 낫다)
List<PlannedAlarm> planAlarms(Feed feed, Subscription sub, DateTime now) {
  final byId = {for (final c in feed.courses) c.id: c};
  final out = <PlannedAlarm>[];

  for (final u in feed.upcoming) {
    final openAt = u.openAtDt;
    if (openAt == null || !openAt.isAfter(now)) continue; // 과거/파싱불가 제외
    final c = byId[u.id];
    if (c != null && !matches(c, sub)) continue;
    if (c == null && !sub.isEmpty) continue;

    var fireAt = openAt.subtract(const Duration(minutes: alarmLeadMin));
    if (!fireAt.isAfter(now)) fireAt = now.add(const Duration(seconds: 15)); // 10분 미만 남음 보정

    final hh = openAt.hour.toString().padLeft(2, '0');
    final mm = openAt.minute.toString().padLeft(2, '0');
    // 날짜는 절대 표기(M/D) — '오늘/내일' 같은 상대 표현은 예약 시점과 발화 시점이
    // 달라서(며칠 전 예약 → 당일 발화) 울리는 순간에 거짓말이 된다(엣지).
    out.add(PlannedAlarm(
      id: stableId(u.id),
      svcid: u.id,
      at: fireAt,
      title: '⏰ ${openAt.month}/${openAt.day} $hh:$mm 접수 시작!',
      body: '[${u.area.isEmpty ? '서울전역' : u.area}] ${u.name}',
      url: c?.url ?? '',
    ));
  }

  out.sort((a, b) => a.at.compareTo(b.at));
  return out.length > maxScheduledAlarms ? out.sublist(0, maxScheduledAlarms) : out;
}
