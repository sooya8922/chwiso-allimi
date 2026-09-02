/// 백그라운드 갱신 오케스트레이터(단일) — workmanager 주기 작업(6시간).
///
/// 통합 설계: 강좌·나들이 두 도메인의 갱신 루틴을 한 번의 실행에서 순차 호출한다.
/// 워크매니저 태스크는 'feed_refresh' 하나만 등록한다(통합 전 두 앱이 같은 태스크명을
/// 각자 등록하던 것을 단일화). 각 도메인은 자기 prefs 키/60초 가드를 독립적으로 쓰므로
/// 한 도메인이 실패해도 다른 도메인은 계속 실행된다(try/catch로 격리).
library;

import 'package:workmanager/workmanager.dart';

import '../event/services/background.dart' as event;
import '../services/background.dart' as course;

const _taskName = 'feed_refresh';

/// 백그라운드 isolate 진입점 — 반드시 top-level + vm:entry-point.
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    return await refreshAllAndNotify();
  });
}

/// 두 도메인 갱신을 순차 실행. 각 도메인은 독립적으로 격리 —
/// 한쪽 실패(네트워크/파싱)가 다른쪽을 막지 않는다. 하나라도 실패하면 false 반환
/// → workmanager 재시도 정책에 맡긴다(다음 주기에 다시 시도).
///
/// [courseRefresh]/[eventRefresh]는 테스트에서 실패/성공을 주입하기 위한 훅(프로덕션은 기본값).
Future<bool> refreshAllAndNotify({
  Future<void> Function()? courseRefresh,
  Future<void> Function()? eventRefresh,
}) async {
  var ok = true;
  try {
    await (courseRefresh ?? course.refreshAndNotify)();
  } catch (_) {
    ok = false;
  }
  try {
    await (eventRefresh ?? event.refreshAndNotify)();
  } catch (_) {
    ok = false;
  }
  return ok;
}

/// 주기 작업 등록 — 앱 시작 시 1회 호출(중복 등록은 update로 무해).
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
