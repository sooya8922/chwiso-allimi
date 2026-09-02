/// 공용 알림 타입 — 강좌/나들이 두 도메인이 함께 쓰는 값 객체와 안정 해시.
/// (통합 전에는 각 도메인 notif_planner.dart에 중복 정의돼 있었다 — 단일화)
///
/// 이 파일은 순수(플러그인/IO 없음)하며, core/notification_service.dart(플랫폼 실행)와
/// 각 도메인 planner(계획 생성)가 공통으로 참조한다.
library;

/// 즉시 알림 하나.
/// [key]는 도메인 안에서 중복 방지용 키(예: "new_S123", "digest_2026-W29").
/// 실제 플랫폼 알림 id는 NotificationService.showInstant가 도메인 프리픽스를 붙여
/// stableId로 파생한다(도메인 간 id 충돌 방지 — burst_summary 등 동일 키 대비).
class PlannedNotification {
  final String key;
  final String title;
  final String body;
  final String url; // 탭 시 열 딥링크 (빈 문자열 = 앱만 열림)

  const PlannedNotification({required this.key, required this.title, required this.body, required this.url});
}

/// 예약 알람 하나(강좌 전용 — 접수 오픈 10분 전 정확 알람).
/// 나들이는 예약 알람이 없다(즉시 알림만).
class PlannedAlarm {
  final int id; // 플랫폼 알람 id (svcid에서 안정적으로 파생 — 재예약 시 같은 id로 덮어씀)
  final String svcid;
  final DateTime at;
  final String title;
  final String body;
  final String url;

  const PlannedAlarm(
      {required this.id,
      required this.svcid,
      required this.at,
      required this.title,
      required this.body,
      required this.url});
}

/// 문자열 → 안정적 31비트 양수 id (dart String.hashCode는 실행마다 달라질 수 있어 직접 FNV-1a).
/// 빈 문자열이면 루프 미실행 → 시드가 31비트 초과(음수화) → 반환 시 마스킹으로 양수 보장.
int stableId(String s) {
  var h = 0x811c9dc5;
  for (final c in s.codeUnits) {
    h ^= c;
    h = (h * 0x01000193) & 0x7fffffff;
  }
  return h & 0x7fffffff;
}
