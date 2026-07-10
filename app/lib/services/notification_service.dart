/// 플랫폼 알림 래퍼 — flutter_local_notifications 호출을 여기 격리.
/// 계획(무엇을/언제)은 notif_planner.dart 순수함수가 만들고, 여기는 실행만 한다.
library;

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import 'package:url_launcher/url_launcher.dart';

import '../logic/notif_planner.dart';

class NotificationService {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static Future<void>? _initFuture; // 동시 진입해도 initialize를 한 번만(Completer 대신 Future 캐시)

  static const _instantChannel = AndroidNotificationDetails(
    'instant', '새 강좌·재오픈 알림',
    channelDescription: '조건에 맞는 강좌가 새로 열리면 알림',
    importance: Importance.high, priority: Priority.high,
  );
  static const _alarmChannel = AndroidNotificationDetails(
    'open_alarm', '접수 오픈 알람',
    channelDescription: '접수 시작 10분 전 알람',
    importance: Importance.max, priority: Priority.max,
    category: AndroidNotificationCategory.alarm,
  );

  /// 데이터/알람 일시는 전부 KST(서울 강좌) — 기기 TZ와 무관하게 고정.
  /// 첫 호출의 Future를 캐시해, 앱 시작 시 addPostFrameCallback과 feed 경로가 거의 동시에
  /// init()을 불러도 initialize가 딱 한 번만 실행되게 한다(중복 초기화 race 방지).
  /// 실패하면 캐시를 비워 다음 호출이 재시도할 수 있게 한다 — 실패 Future가 캐시되면
  /// 그 세션 내내 알림 기능이 죽어버리는 것을 방지.
  static Future<void> init() {
    return _initFuture ??= _doInit().catchError((e) {
      _initFuture = null; // 다음 init()에서 재시도 가능
      throw e;
    });
  }

  static Future<void> _doInit() async {
    tzdata.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('Asia/Seoul'));
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
      onDidReceiveNotificationResponse: _onTap,
    );
    // 앱이 종료된 상태에서 알림 탭으로 실행된 경우, 그 payload(딥링크)를 처리.
    // 이건 부가기능(best-effort)이라 자체 try-catch로 격리 — 여기서 실패해도 이미 성공한
    // _plugin.initialize()(핵심 알림 초기화)까지 무효화되면 안 됨(일부 OEM에서 이 API가 던짐).
    try {
      final launch = await _plugin.getNotificationAppLaunchDetails();
      if (launch?.didNotificationLaunchApp ?? false) {
        final resp = launch!.notificationResponse;
        if (resp != null) _onTap(resp);
      }
    } catch (_) {/* cold-start 딥링크만 유실, 알림 기능은 정상 */}
  }

  static const _testAlarmId = 999999901; // 진단용 테스트 알람 id (재예약 취소에서 제외)

  static void _onTap(NotificationResponse resp) {
    final url = resp.payload;
    if (url != null && url.startsWith('http')) {
      final uri = Uri.tryParse(url); // 파손 URL이어도 탭 핸들러가 죽지 않게
      if (uri != null) launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  /// Android 13+ 알림 권한 요청. 결과: 허용 여부(다른 플랫폼/버전은 true 취급)
  static Future<bool> requestPermission() async {
    await init();
    final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    if (android == null) return true;
    final granted = await android.requestNotificationsPermission();
    return granted ?? true;
  }

  static Future<void> showInstant(PlannedNotification n) async {
    await init();
    await _plugin.show(
      id: stableId(n.key),
      title: n.title,
      body: n.body,
      notificationDetails: const NotificationDetails(android: _instantChannel),
      payload: n.url,
    );
  }

  /// 알람 재계획: 기존 예약 전부 취소 후 새 계획으로 예약(피드가 바뀌었을 수 있으므로).
  /// 정확알람 권한이 없으면 inexact로 폴백(늦을 수 있지만 안 울리는 것보단 낫다).
  static Future<void> rescheduleAlarms(List<PlannedAlarm> alarms) async {
    await init();
    // 예약(pending)만 개별 취소 — 이미 표시된 알림은 건드리지 않는다.
    // 진단용 테스트 알람은 제외(재예약이 M4 검증 중인 테스트 알람을 지우면 안 됨).
    for (final p in await _plugin.pendingNotificationRequests()) {
      if (p.id == _testAlarmId) continue;
      await _plugin.cancel(id: p.id);
    }
    final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    final exactOk = await android?.canScheduleExactNotifications() ?? false;
    for (final a in alarms) {
      // a.at은 KST 월클럭(naive). TZDateTime.from은 기기 TZ의 epoch로 해석해버리므로
      // (해외 기기 엣지) 성분으로 Asia/Seoul 시각을 직접 조립한다.
      final atKst = tz.TZDateTime(tz.local, a.at.year, a.at.month, a.at.day, a.at.hour, a.at.minute, a.at.second);
      await _plugin.zonedSchedule(
        id: a.id,
        title: a.title,
        body: a.body,
        scheduledDate: atKst,
        notificationDetails: const NotificationDetails(android: _alarmChannel),
        androidScheduleMode:
            exactOk ? AndroidScheduleMode.exactAllowWhileIdle : AndroidScheduleMode.inexactAllowWhileIdle,
        payload: a.url,
      );
    }
  }

  static Future<int> pendingCount() async {
    await init();
    return (await _plugin.pendingNotificationRequests()).length;
  }

  /// 진단용: 정확알람 권한 상태 (M4 — 기기 설정 메뉴가 기종마다 달라 앱에서 직접 확인)
  static Future<bool> canExact() async {
    await init();
    final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    return await android?.canScheduleExactNotifications() ?? false;
  }

  /// 진단용: 예약된 알람 목록
  static Future<List<PendingNotificationRequest>> pendingList() async {
    await init();
    return _plugin.pendingNotificationRequests();
  }

  /// 정확알람 권한 요청 — 시스템의 '알람 및 리마인더' 설정(우리 앱 페이지)을 직접 연다.
  static Future<bool> requestExact() async {
    await init();
    final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    if (android == null) return false;
    await android.requestExactAlarmsPermission();
    return await android.canScheduleExactNotifications() ?? false;
  }

  /// 진단용: 1분 후 테스트 알람 — 알람 '전달' 자체가 되는지 즉시 검증(M4).
  /// 실제 알람과 동일한 채널/모드를 쓰므로 이게 울리면 전달 경로는 정상.
  static Future<void> scheduleTestAlarm() async {
    await init();
    final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    final exactOk = await android?.canScheduleExactNotifications() ?? false;
    final at = tz.TZDateTime.now(tz.local).add(const Duration(minutes: 1));
    await _plugin.zonedSchedule(
      id: _testAlarmId,
      title: '🔔 테스트 알람',
      body: '이게 보이면 알람 전달 정상 (${at.hour}:${at.minute.toString().padLeft(2, '0')} 예약분)',
      scheduledDate: at,
      notificationDetails: const NotificationDetails(android: _alarmChannel),
      androidScheduleMode:
          exactOk ? AndroidScheduleMode.exactAllowWhileIdle : AndroidScheduleMode.inexactAllowWhileIdle,
    );
  }
}
