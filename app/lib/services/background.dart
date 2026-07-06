/// 백그라운드 갱신 — workmanager 주기 작업(6시간).
/// 파이프라인이 하루 4회 feed를 갱신하므로 6시간 주기면 놓침 없이 따라간다.
///
/// 한 번의 실행에서: feed fetch → 즉시알림(신규/재오픈) 발송 → 광클 알람 재예약.
/// 앱을 열 때도 같은 replan이 돌므로(홈 화면), 백그라운드는 보조 경로다.
library;

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import '../logic/notif_planner.dart';
import '../models/course.dart';
import 'feed_service.dart';
import 'notification_service.dart';
import 'prefs_service.dart';

const _taskName = 'feed_refresh';
const _notifiedKey = 'notified_keys_v1';

/// 백그라운드 isolate 진입점 — 반드시 top-level + vm:entry-point.
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    try {
      await refreshAndNotify();
      return true;
    } catch (_) {
      return false; // 실패 → workmanager 재시도 정책에 맡김
    }
  });
}

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
    final notified =
        ((json.decode(storedRaw ?? '[]') as List).map((e) => e.toString())).toSet();
    final plan = planInstantNotifications(feed, sub, notified);
    if (storedRaw != null) {
      // 평상시: 새 이벤트만 발송
      for (final n in plan.toShow) {
        await NotificationService.showInstant(n);
      }
    }
    // 첫 실행(storedRaw == null)은 발송 없이 기준선만 저장 — 설치 직후
    // "지난 7일치 재오픈 알림 폭탄"(M4 실기기 실측) 방지.
    // 발송 여부와 무관하게 이번 feed의 모든 키를 '본 것'으로 저장:
    // 사라진 이벤트 키는 자연히 정리되고, 억제(쿨다운/조건 밖) 이벤트도 소급 발화하지 않는다.
    await sp.setString(_notifiedKey, json.encode(plan.allKeys.toList()));
  }

  // 2) 광클 알람 재예약 (now도 KST로 — 기기 TZ 무관, 재예약은 멱등)
  // 조용시간 정책: alarmsExempt(기본)면 알람은 그대로, 아니면 조용시간 발화분 제거
  final alarms = applyQuietToAlarms(planAlarms(feed, sub, nowKst), quietCfg);
  await NotificationService.rescheduleAlarms(alarms);
}

/// 주기 작업 등록 — 앱 시작 시 1회 호출(중복 등록은 replace로 무해).
Future<void> registerBackgroundRefresh() async {
  await Workmanager().initialize(callbackDispatcher);
  await Workmanager().registerPeriodicTask(
    _taskName, _taskName,
    frequency: const Duration(hours: 6),
    constraints: Constraints(networkType: NetworkType.connected),
    existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
    backoffPolicy: BackoffPolicy.linear,
  );
}
