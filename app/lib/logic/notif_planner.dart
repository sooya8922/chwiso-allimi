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
DateTime kstNow() => DateTime.now().toUtc().add(const Duration(hours: 9));

/// svcid → 안정적 32비트 양수 id (dart String.hashCode는 실행마다 달라질 수 있어 직접 FNV-1a)
int stableId(String svcid) {
  var h = 0x811c9dc5;
  for (final c in svcid.codeUnits) {
    h ^= c;
    h = (h * 0x01000193) & 0x7fffffff;
  }
  return h;
}

/// 1) 신규/재오픈 즉시 알림 계획.
/// [notified]: 이미 보낸 키 셋 — 여기 있는 건 다시 안 보낸다(호출측이 저장/로드).
List<PlannedNotification> planInstantNotifications(Feed feed, Subscription sub, Set<String> notified) {
  final byId = {for (final c in feed.courses) c.id: c};
  final out = <PlannedNotification>[];

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

  for (final r in feed.reopened) {
    if (!r.inWindow) continue; // 접수기간 밖 재오픈은 신청 불가 → 알림 가치 없음
    final key = 'reopen_${r.id}_${r.at}';
    if (notified.contains(key)) continue;
    final c = byId[r.id];
    if (c != null && !matches(c, sub)) continue;
    if (c == null && !sub.isEmpty) continue;
    // 지금도 접수중인 것만 (재오픈 후 이미 다시 마감됐으면 헛알림)
    if (c != null && !c.isOpen) continue;
    out.add(PlannedNotification(
      key: key,
      title: '🔓 마감됐던 강좌가 다시 열렸어요',
      body: '[${r.area.isEmpty ? '서울전역' : r.area}] ${r.name}',
      url: c?.url ?? '',
    ));
  }
  return out;
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
    out.add(PlannedAlarm(
      id: stableId(u.id),
      svcid: u.id,
      at: fireAt,
      title: '⏰ $hh:$mm 접수 시작!',
      body: '[${u.area.isEmpty ? '서울전역' : u.area}] ${u.name}',
      url: c?.url ?? '',
    ));
  }

  out.sort((a, b) => a.at.compareTo(b.at));
  return out.length > maxScheduledAlarms ? out.sublist(0, maxScheduledAlarms) : out;
}

/// notified 키 셋 정리 — feed에서 사라진 지 오래된 키가 무한히 쌓이는 것 방지.
/// 현재 feed에서 다시 만들 수 있는 키만 유지한다(사라진 키는 재발송 위험도 없음).
Set<String> pruneNotified(Set<String> notified, Feed feed) {
  final valid = <String>{
    ...feed.newCourses.map((n) => 'new_${n.id}'),
    ...feed.reopened.map((r) => 'reopen_${r.id}_${r.at}'),
  };
  return notified.intersection(valid);
}
