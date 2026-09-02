/// 나들이 알림 "계획" — 순수 함수만(플러그인/IO 없음, 단위테스트 대상).
///
/// 두 종류의 알림을 계획한다:
///  1) 즉시 알림: 구독조건에 맞는 신규 등록 행사 — 중복 발송 방지(notified 셋)
///  2) 주간 다이제스트: 목 18시~금 22시 창에서 주 1회, "이번 주말 아이랑" 요약
///
/// 공용 타입(PlannedNotification/QuietConfig/kstNow/inQuietHours/stableId)은 core/로
/// 이동했고 여기서 re-export 한다 → 기존 import 경로(notif_planner.dart)가 그대로 동작.
library;

import '../../core/notif_types.dart';
import '../../core/time.dart';
import '../models/event.dart';
import 'matcher.dart';

export '../../core/notif_types.dart'; // PlannedNotification, PlannedAlarm, stableId
export '../../core/time.dart'; // QuietConfig, kstNow, inQuietHours

/// 즉시알림이 한 번에 [threshold]건을 넘으면 요약 1건으로 묶는다 —
/// 필터 없이 쓰는 사용자가 아침마다 수십 건 도배당하는 것 방지(chwiso 실기기 교훈).
List<PlannedNotification> summarizeBurst(List<PlannedNotification> toShow, {int threshold = 5}) {
  if (toShow.length <= threshold) return toShow;
  return [
    PlannedNotification(
      key: 'burst_summary',
      title: '🧺 새 나들이 소식 ${toShow.length}건',
      body: '새로 올라온 행사 ${toShow.length}건 — 눌러서 확인하세요',
      url: '',
    ),
  ];
}

/// 다음(또는 진행 중인) 주말의 [토, 일] 날짜 쌍. 시간 성분은 00:00.
/// 토·일 당일이라면 '이번 주말'을 유지한다(주말 중에도 주말 행사를 보여줘야 하므로).
(DateTime sat, DateTime sun) weekendOf(DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  // weekday: 월1 … 토6 일7
  final int toSat;
  if (now.weekday == DateTime.sunday) {
    toSat = -1; // 일요일엔 어제(토)부터의 주말
  } else {
    toSat = DateTime.saturday - now.weekday;
  }
  final sat = today.add(Duration(days: toSat));
  return (sat, sat.add(const Duration(days: 1)));
}

/// 이번 주말과 겹치고 구독조건에 맞는 행사들.
List<Event> weekendEvents(Feed feed, Subscription sub, DateTime now) {
  final (sat, sun) = weekendOf(now);
  final sunEnd = DateTime(sun.year, sun.month, sun.day, 23, 59);
  return filterEvents(feed.events.where((e) => e.overlaps(sat, sunEnd)).toList(), sub);
}

/// ISO 주차 키 (예: "2026-W29") — 다이제스트 '주 1회' 가드에 사용.
String isoWeekKey(DateTime d) {
  // ISO 8601: 그 주의 목요일이 속한 해가 그 주의 연도
  final thursday = d.add(Duration(days: 4 - (d.weekday == 7 ? 7 : d.weekday)));
  final firstDay = DateTime(thursday.year, 1, 1);
  final week = ((thursday.difference(firstDay).inDays) / 7).floor() + 1;
  return '${thursday.year}-W${week.toString().padLeft(2, '0')}';
}

/// 주간 다이제스트 발송 창인가 — 목 18시 이후 ~ 금 22시 전.
/// (파이프라인이 아침에 피드를 갱신하고, 주말 계획은 목·금 저녁에 세운다는 가정)
bool inDigestWindow(DateTime now) {
  if (now.weekday == DateTime.thursday) return now.hour >= 18;
  if (now.weekday == DateTime.friday) return now.hour < 22;
  return false;
}

/// 2) 주간 다이제스트 계획. 발송할 게 아니면 null.
/// [lastDigestWeek]: 마지막으로 다이제스트를 보낸 주차 키(SharedPreferences 저장) — 주 1회 가드.
PlannedNotification? planDigest(Feed feed, Subscription sub, DateTime now, String? lastDigestWeek) {
  if (!inDigestWindow(now)) return null;
  final week = isoWeekKey(now);
  if (lastDigestWeek == week) return null;
  final list = weekendEvents(feed, sub, now);
  if (list.isEmpty) return null;
  final byArea = <String, int>{};
  for (final e in list) {
    byArea[e.area] = (byArea[e.area] ?? 0) + 1;
  }
  final parts = ['서울', '경기', '인천']
      .where((a) => (byArea[a] ?? 0) > 0)
      .map((a) => '$a ${byArea[a]}')
      .join(' · ');
  final free = list.where((e) => e.free == true).length;
  return PlannedNotification(
    key: 'digest_$week',
    title: '🧺 이번 주말 아이랑 갈 만한 곳 ${list.length}곳',
    body: '$parts${free > 0 ? ' — 무료 $free곳' : ''} · 눌러서 골라보세요',
    url: '',
  );
}

/// 즉시 알림 계획 결과.
/// [toShow]: 지금 발송할 알림. [allKeys]: 이번 feed의 모든 이벤트 키 —
/// 발송 여부와 무관하게 전부 '본 것'으로 저장해야 한다(조건 변경이
/// 과거 이벤트를 소급 발화시키는 엣지 방지 — chwiso 의미론).
class InstantPlan {
  final List<PlannedNotification> toShow;
  final Set<String> allKeys;

  const InstantPlan({required this.toShow, required this.allKeys});
}

/// 1) 신규 행사 즉시 알림 계획.
/// [notified]: 이미 본 키 셋 — 여기 있는 건 다시 안 보낸다(호출측이 저장/로드).
/// 이미 끝난 행사는 알리지 않는다(48h 신규 창 안에서도 하루짜리 행사는 지나갈 수 있음).
InstantPlan planInstantNotifications(Feed feed, Subscription sub, Set<String> notified, {DateTime? now}) {
  final nowKst = now ?? kstNow();
  final byId = {for (final e in feed.events) e.id: e};
  final out = <PlannedNotification>[];
  final allKeys = <String>{for (final n in feed.newEvents) 'new_${n.id}'};

  for (final n in feed.newEvents) {
    final key = 'new_${n.id}';
    if (notified.contains(key)) continue;
    final e = byId[n.id];
    if (e == null) continue; // 상세를 모르면 조건 판정 불가 → 보수적으로 스킵
    if (!matches(e, sub)) continue;
    if (e.ended(nowKst)) continue;
    final where = [e.area, if (e.sigungu.isNotEmpty) e.sigungu].join(' ');
    out.add(PlannedNotification(
      key: key,
      title: '🆕 새 나들이 행사',
      body: '[$where] ${e.title} (${e.periodLabel}${e.free == true ? ' · 무료' : ''})',
      url: e.url,
    ));
  }
  return InstantPlan(toShow: out, allKeys: allKeys);
}
