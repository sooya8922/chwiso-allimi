/// 플랫폼 알림 래퍼(단일) — flutter_local_notifications 호출을 여기 격리.
/// 계획(무엇을/언제)은 각 도메인 planner 순수함수가 만들고, 여기는 실행만 한다.
///
/// 통합 설계:
///  - 채널 4개를 도메인·용도별로 분리 → 사용자가 강좌/나들이 알림을 개별 음소거 가능.
///    (통합 전 두 앱이 같은 'instant' 채널 id를 써서 하나로 뭉개지던 문제 해소)
///  - 알림 id = stableId(idPrefix + key). 도메인 프리픽스('c:'/'e:')로 id 공간을 분리 →
///    강좌·나들이의 동일 키(예: 'burst_summary')가 서로 덮어쓰던 충돌 해소.
///  - 예약 알람(zonedSchedule)은 강좌만 사용. 나들이는 show()(즉시)만 → pending 목록엔
///    강좌 알람만 존재하므로 rescheduleAlarms의 전체 취소가 나들이 알림을 건드리지 않는다.
///    ⚠️ 만약 나중에 나들이에 예약 알람을 추가하면 이 가정이 깨진다(그때는 취소를 채널/키로 한정할 것).
library;

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import 'package:url_launcher/url_launcher.dart';

import 'notif_types.dart';

/// 알림 채널 종류 — 도메인·용도별 분리(개별 음소거 지원).
enum NotifKind { courseInstant, courseAlarm, eventInstant, eventDigest }

class NotificationService {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static Future<void>? _initFuture; // 동시 진입해도 initialize를 한 번만(Future 캐시)

  // 강좌 — 새 강좌·재오픈 즉시 알림.
  // 채널 id는 통합 전('instant')과 동일하게 유지 → 기존 v1.0 사용자가 업그레이드해도
  // 설정의 알림 채널이 그대로 이어지고 옛 채널이 잔존하지 않는다. (나들이만 새 id 사용)
  static const _courseInstant = AndroidNotificationDetails(
    'instant', '새 강좌·재오픈 알림',
    channelDescription: '조건에 맞는 강좌가 새로 열리면 알림',
    importance: Importance.high, priority: Priority.high,
  );
  // 강좌 — 접수 오픈 10분 전 광클 알람 (id는 통합 전 'open_alarm' 유지)
  static const _courseAlarm = AndroidNotificationDetails(
    'open_alarm', '접수 오픈 알람',
    channelDescription: '접수 시작 10분 전 알람',
    importance: Importance.max, priority: Priority.max,
    category: AndroidNotificationCategory.alarm,
  );
  // 나들이 — 새 행사 즉시 알림
  static const _eventInstant = AndroidNotificationDetails(
    'event_instant', '새 나들이 행사 알림',
    channelDescription: '조건에 맞는 나들이 행사가 새로 올라오면 알림',
    importance: Importance.high, priority: Priority.high,
  );
  // 나들이 — 주말 다이제스트
  static const _eventDigest = AndroidNotificationDetails(
    'event_digest', '주말 나들이 다이제스트',
    channelDescription: '목·금 저녁, 이번 주말 아이랑 갈 만한 곳 요약',
    importance: Importance.high, priority: Priority.high,
  );

  static AndroidNotificationDetails _details(NotifKind k) {
    switch (k) {
      case NotifKind.courseInstant:
        return _courseInstant;
      case NotifKind.courseAlarm:
        return _courseAlarm;
      case NotifKind.eventInstant:
        return _eventInstant;
      case NotifKind.eventDigest:
        return _eventDigest;
    }
  }

  /// 알림 id 도메인 프리픽스 — 같은 key라도 도메인이 다르면 다른 id가 되도록.
  static String _prefix(NotifKind k) {
    switch (k) {
      case NotifKind.courseInstant:
      case NotifKind.courseAlarm:
        return 'c:';
      case NotifKind.eventInstant:
      case NotifKind.eventDigest:
        return 'e:';
    }
  }

  /// 데이터/알람 일시는 전부 KST — 기기 TZ와 무관하게 고정.
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
    // best-effort — 실패해도 이미 성공한 _plugin.initialize()까지 무효화되면 안 됨(일부 OEM에서 던짐).
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

  /// 즉시 알림 발송. [kind]로 채널과 id 프리픽스가 결정된다.
  static Future<void> showInstant(PlannedNotification n, {required NotifKind kind}) async {
    await init();
    await _plugin.show(
      id: stableId('${_prefix(kind)}${n.key}'),
      title: n.title,
      body: n.body,
      notificationDetails: NotificationDetails(android: _details(kind)),
      payload: n.url,
    );
  }

  /// 강좌 알람 재계획: 기존 예약 전부 취소 후 새 계획으로 예약(피드가 바뀌었을 수 있으므로).
  /// 정확알람 권한이 없으면 inexact로 폴백(늦을 수 있지만 안 울리는 것보단 낫다).
  /// ⚠️ pending 전체 취소 — 현재는 강좌 알람만 예약되므로 안전(나들이는 즉시 알림만).
  static Future<void> rescheduleAlarms(List<PlannedAlarm> alarms) async {
    await init();
    // 예약(pending)만 개별 취소 — 이미 표시된 알림은 건드리지 않는다.
    // 진단용 테스트 알람은 제외(재예약이 검증 중인 테스트 알람을 지우면 안 됨).
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
        notificationDetails: const NotificationDetails(android: _courseAlarm),
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

  /// 진단용: 정확알람 권한 상태 (기기 설정 메뉴가 기종마다 달라 앱에서 직접 확인)
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

  /// 진단용(강좌): 1분 후 테스트 알람 — 알람 '전달' 자체가 되는지 즉시 검증.
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
      notificationDetails: const NotificationDetails(android: _courseAlarm),
      androidScheduleMode:
          exactOk ? AndroidScheduleMode.exactAllowWhileIdle : AndroidScheduleMode.inexactAllowWhileIdle,
    );
  }

  /// 진단용(나들이): 즉시 테스트 알림 — 알림 '전달' 자체가 되는지 검증.
  static Future<void> showTestNotification() async {
    await init();
    await _plugin.show(
      id: _testAlarmId,
      title: '🔔 테스트 알림',
      body: '이게 보이면 알림 경로 정상',
      notificationDetails: const NotificationDetails(android: _eventInstant),
    );
  }
}
