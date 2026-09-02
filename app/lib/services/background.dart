/// 강좌 도메인 갱신 루틴 — 포그라운드(앱 열림)와 백그라운드(core 오케스트레이터) 양쪽에서 호출.
///
/// 한 번의 실행에서: feed fetch → 즉시알림(신규/재오픈) 발송 → 광클 알람 재예약.
/// 워크매니저 등록/진입점은 core/background.dart가 단일 관리한다(나들이와 통합).
///
/// prefs 키는 통합 후에도 강좌 전용으로 유지(notified_keys_v1 / notify_run_ts_v1) —
/// 기존 v1.0 사용자 상태를 그대로 보존한다. 나들이는 별도 네임스페이스 키를 쓴다.
library;

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../core/notification_service.dart';
import '../logic/notif_planner.dart';
import '../models/course.dart';
import 'feed_service.dart';
import 'prefs_service.dart';

const _notifiedKey = 'notified_keys_v1';
const _lastRunKey = 'notify_run_ts_v1';

/// 공용 갱신 루틴 — 포그라운드(앱 열림)와 백그라운드 양쪽에서 호출.
/// [now]는 테스트 주입용(기본 = 실제 KST 시각).
Future<void> refreshAndNotify({Feed? preloaded, DateTime? now}) async {
  final feed = preloaded ?? (await FeedService().load()).feed;
  final prefs = PrefsService();
  final sub = await prefs.load();
  final quietCfg = await prefs.loadQuiet();
  final nowKst = now ?? kstNow();

  final sp = await SharedPreferences.getInstance();

  // 1) 즉시 알림 (신규/재오픈)
  // 이중 실행 가드: 앱 오픈과 WorkManager가 거의 동시에 돌면(별도 isolate라 메모리 락 불가)
  // 같은 알림이 두 번 나간다 → 60초 내 재실행이면 즉시알림 파트는 스킵(알람 재예약은 멱등이라 진행).
  final nowMs = DateTime.now().millisecondsSinceEpoch;
  final lastMs = sp.getInt(_lastRunKey) ?? 0;
  final storedRaw = sp.getString(_notifiedKey);
  // 조용시간(22~08시 KST)에는 즉시알림을 발송도 저장도 하지 않는다 → 밤새 생긴
  // 이벤트는 '안 본' 상태로 남아 아침 첫 확인 때 알림된다(새벽 05:56 알림 — M4 피드백).
  // 단 첫 실행 기준선(storedRaw==null)은 발송이 없으므로 조용시간에도 저장한다
  // (밤에 설치 → 아침에 지난 7일치 폭탄 나는 엣지 방지).
  final quiet = inQuietHours(nowKst, quietCfg) && storedRaw != null;
  if (!quiet && (nowMs - lastMs).abs() > 60000) {
    await sp.setInt(_lastRunKey, nowMs); // 먼저 마킹해 레이스 창 최소화
    // 저장소 손상(쓰기 중 크래시 등) 시 json.decode가 던지면 이후 모든 알림이 영구 실패한다
    // → try/catch로 빈 셋 폴백 + 손상 키 제거(self-heal). 최악은 알림 1회 중복, 영구 실패 아님.
    Set<String> notified;
    try {
      notified = (json.decode(storedRaw ?? '[]') as List).map((e) => e.toString()).toSet();
    } catch (_) {
      notified = {};
      await sp.remove(_notifiedKey);
    }
    final plan = planInstantNotifications(feed, sub, notified, now: nowKst);
    // allKeys를 발송 '전에' 저장한다: showInstant가 배치 도중 던져도(플랫폼 오류 등)
    // 다음 실행에서 같은 알림을 재발송하지 않게 — 최악은 중복이 아니라 누락(더 안전).
    // 첫 실행(storedRaw == null)은 발송 없이 기준선만 저장(설치 직후 7일치 폭탄 방지).
    await sp.setString(_notifiedKey, json.encode(plan.allKeys.toList()));
    if (storedRaw != null) {
      // 평상시: 새 이벤트만 발송 (폭주 시 요약 1건으로 묶음)
      for (final n in summarizeBurst(plan.toShow)) {
        await NotificationService.showInstant(n, kind: NotifKind.courseInstant);
      }
    }
  }

  // 2) 광클 알람 재예약 (now도 KST로 — 기기 TZ 무관, 재예약은 멱등)
  // 조용시간 정책: alarmsExempt(기본)면 알람은 그대로, 아니면 조용시간 발화분 제거
  final alarms = applyQuietToAlarms(planAlarms(feed, sub, nowKst), quietCfg);
  await NotificationService.rescheduleAlarms(alarms);
}
