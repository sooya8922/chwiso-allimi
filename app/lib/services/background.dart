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

/// 공용 갱신 루틴 — 포그라운드(앱 열림)와 백그라운드 양쪽에서 호출.
Future<void> refreshAndNotify({Feed? preloaded}) async {
  final feed = preloaded ?? (await FeedService().load()).feed;
  final sub = await PrefsService().load();

  final sp = await SharedPreferences.getInstance();
  final notified = ((json.decode(sp.getString(_notifiedKey) ?? '[]') as List).map((e) => e.toString())).toSet();

  // 1) 즉시 알림 (신규/재오픈)
  final instants = planInstantNotifications(feed, sub, notified);
  for (final n in instants) {
    await NotificationService.showInstant(n);
    notified.add(n.key);
  }
  await sp.setString(_notifiedKey, json.encode(pruneNotified(notified, feed).toList()));

  // 2) 광클 알람 재예약 (now도 KST로 — 기기 TZ 무관)
  final alarms = planAlarms(feed, sub, kstNow());
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
