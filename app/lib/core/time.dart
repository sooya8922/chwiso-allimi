/// 공용 시간·조용시간 유틸 — 강좌/나들이 공통. 순수 함수(IO 없음).
/// (통합 전 각 도메인에 동일 코드가 중복돼 있었다 — 단일화. QuietConfig는
///  강좌판(alarmsExempt 포함)을 상위집합으로 채택 → 두 도메인이 quiet_config_v1을 공유)
library;

/// 현재 KST 월클럭(naive) — 기기 TZ가 한국이 아니어도(해외여행 엣지) 데이터(KST)와 일관되게 비교.
///
/// 반드시 isUtc=false(naive)로 반환해야 한다. toUtc().add(9h)를 그대로 반환하면
/// isUtc=true 깃발이 남아 naive로 파싱된 feed 시각과의 비교(epoch 기반)가 9시간 틀어진다
/// — 오픈 9시간 이내 알람이 전부 삭제되고 9시간 경계의 알람이 즉시 발화하던
/// chwiso M4 실기기 대참사(7/6 08:50 미발화, 7/7 05:59 조기발화)의 근본 원인.
DateTime kstNow() {
  final u = DateTime.now().toUtc().add(const Duration(hours: 9));
  return DateTime(u.year, u.month, u.day, u.hour, u.minute, u.second);
}

/// 조용시간 설정 — 사용자가 지정(기본 22시~8시). 즉시알림(신규/재오픈)은 이 시간대에
/// 발송하지 않고 다음 확인 때로 미룬다(배치성 소식이라 늦어도 손해 없음 — chwiso M4 피드백).
/// [alarmsExempt]=true(기본)면 ⏰ 강좌 광클 알람은 예외(자정 오픈을 잡으려고 건 알람은 울리는 게 목적),
/// false면 알람도 조용시간에 걸리는 건 예약하지 않는다.
/// (나들이는 예약 알람이 없어 alarmsExempt를 참조하지 않는다 — 필드는 공유되지만 무해)
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
