/// 강좌 알림 "계획" — 순수 함수만(플러그인/IO 없음, 단위테스트 대상).
///
/// 두 종류의 알림을 계획한다:
///  1) 즉시 알림: 구독조건에 맞는 신규 등록/재오픈 — 중복 발송 방지(notified 셋)
///  2) 광클 알람: 구독조건에 맞는 접수 오픈예정 — 오픈 10분 전 정확 알람
///
/// 공용 타입(PlannedNotification/PlannedAlarm/QuietConfig/kstNow/inQuietHours/stableId)은
/// core/로 이동했고, 여기서 re-export 한다 → 기존 import 경로(notif_planner.dart)가 그대로 동작.
library;

import '../core/notif_types.dart';
import '../core/time.dart';
import '../models/course.dart';
import 'matcher.dart';

export '../core/notif_types.dart'; // PlannedNotification, PlannedAlarm, stableId
export '../core/time.dart'; // QuietConfig, kstNow, inQuietHours

/// 광클 알람 리드타임(오픈 몇 분 전에 울릴지)
const alarmLeadMin = 10;

/// Android 정확알람 남발 방지 상한(가까운 순으로 자른다)
const maxScheduledAlarms = 50;

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
      // 알람 id도 도메인 프리픽스로 파생 → 강좌 즉시알림('c:new_'…)·나들이('e:'…)와 id 공간을
      // 확실히 분리(교집합 0). 재예약은 pending 전체취소 후 재생성이라 업그레이드 시에도 안전.
      id: stableId('c:alarm:${u.id}'),
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
