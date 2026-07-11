import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../logic/matcher.dart';
import '../logic/notif_planner.dart';
import '../models/course.dart';
import '../services/feed_service.dart';
import '../services/notification_service.dart';
import '../services/prefs_service.dart';
import '../widgets/course_card.dart';
import '../widgets/filter_sheet.dart';
import 'culture_centers_screen.dart';

/// 홈 — 탭 3개: 접수중 / 오픈예정 / 새소식(신규+재오픈)
/// 서비스는 주입 가능(테스트에서 페이크로 교체 — 네트워크/플러그인 비의존).
class HomeScreen extends StatefulWidget {
  final FeedService? feedService;
  final PrefsService? prefsService;

  /// feed 로드/필터 변경 성공 시 호출 — main이 알림 재계획을 꽂는다(테스트에선 null).
  final Future<void> Function(Feed feed)? onFeedLoaded;

  /// 알림/백그라운드 초기화 오류(진단용 배너). null이면 정상.
  final ValueListenable<String?>? initError;

  /// 현재 시각 공급자 — 테스트에서 고정 시각 주입용.
  /// 표시 로직(build)은 kstNow, 라이프사이클 경과시간 판정은 DateTime.now를 기본으로 쓴다
  /// (후자는 경과 밀리초만 보므로 TZ 무관 — 두 기본값 차이는 무해).
  final DateTime Function()? clock;

  const HomeScreen(
      {super.key, this.feedService, this.prefsService, this.onFeedLoaded, this.initError, this.clock});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  late final FeedService _feedSvc = widget.feedService ?? FeedService();
  late final PrefsService _prefsSvc = widget.prefsService ?? PrefsService();

  Feed? _feed;
  bool _fromCache = false;
  Object? _error;
  Subscription _sub = const Subscription();
  QuietConfig _quiet = const QuietConfig();
  DateTime? _lastRefresh; // 포그라운드 복귀 시 과도한 새로고침 방지용

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _init();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 백그라운드→포그라운드 복귀 시 최신 feed로 갱신(알림 탭으로 복귀 등).
    // 단 3분 내 재개는 스킵 — 화면 전환 반복에 매번 네트워크 치지 않도록.
    if (state == AppLifecycleState.resumed) {
      final last = _lastRefresh;
      final now = (widget.clock ?? DateTime.now)();
      if (last == null || now.difference(last).inMinutes >= 3) {
        _refresh();
      }
    }
  }

  bool _refreshing = false;

  Future<void> _init() async {
    // prefs 로드 실패(일부 OEM 저장소 이슈)여도 기본값으로 진행 — 무한 로딩 스피너 방지.
    try {
      _sub = await _prefsSvc.load();
      _quiet = await _prefsSvc.loadQuiet();
    } catch (_) {/* 필드 기본값 사용 */}
    await _refresh();
  }

  Future<void> _refresh() async {
    if (_refreshing) return; // 중복 호출(연타/동시 pull) 디바운스
    _refreshing = true;
    setState(() => _error = null);
    try {
      final r = await _feedSvc.load();
      setState(() {
        _feed = r.feed;
        _fromCache = r.fromCache;
      });
      _lastRefresh = (widget.clock ?? DateTime.now)();
      // 알림 재계획(주입된 경우만). 실패해도 화면은 정상 동작해야 하므로 삼킨다.
      try {
        await widget.onFeedLoaded?.call(r.feed);
      } catch (_) {}
    } catch (e) {
      // feed 버전 불일치는 네트워크 문제가 아니라 앱 업데이트 필요 — 메시지를 구분.
      final isVersion = e is FormatException && e.message.contains('feed version');
      setState(() => _error = isVersion ? '앱을 업데이트해 주세요 (새 데이터 형식)' : e);
    } finally {
      _refreshing = false;
    }
  }

  List<String> get _areas {
    final s = (_feed?.courses ?? []).map((c) => c.area).where((a) => a.isNotEmpty).toSet().toList()..sort();
    return s;
  }

  Future<void> _openFilter() async {
    final result = await showModalBottomSheet<FilterResult>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => FilterSheet(initial: _sub, initialQuiet: _quiet, availableAreas: _areas),
    );
    if (result != null) {
      setState(() {
        _sub = result.sub;
        _quiet = result.quiet;
      });
      try {
        await _prefsSvc.save(result.sub);
        await _prefsSvc.saveQuiet(result.quiet);
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('설정 저장 실패 — 앱 재시작 시 이전 설정으로 돌아갈 수 있어요')));
        }
      }
      // 조건/조용시간이 바뀌면 알람 대상도 바뀐다 → 재계획
      final f = _feed;
      if (f != null) {
        try {
          await widget.onFeedLoaded?.call(f);
        } catch (_) {}
      }
    }
  }

  /// 진단 시트 — 알림이 실제로 예약/허용됐는지 앱 안에서 확인(M4 검증 도구).
  /// 기기 설정 메뉴가 기종마다 달라서 여기서 직접 보여준다.
  Future<void> _showDiagnostics() async {
    var exact = '확인 불가';
    var pending = '확인 불가';
    var canExactNow = false;
    try {
      canExactNow = await NotificationService.canExact();
      exact = canExactNow ? '✅ 허용 — 정시에 울림' : '⚠️ 미허용 — 몇 분 늦을 수 있음';
      final list = await NotificationService.pendingList();
      pending = '${list.length}개';
    } catch (e) {
      exact = '오류: $e';
    }
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('알림 상태', style: Theme.of(ctx).textTheme.titleLarge),
              const SizedBox(height: 12),
              Text('정시 알람: $exact'),
              Text('예약된 알람: $pending'),
              const SizedBox(height: 8),
              Text(
                '알림이 오지 않으면 아래 버튼으로 테스트해보세요. '
                '테스트 알람이 안 온다면 기기의 절전/배터리 설정에서 이 앱을 예외로 추가해주세요.',
                style: Theme.of(ctx).textTheme.bodySmall,
              ),
              const SizedBox(height: 16),
              // 알람 전달 자체를 즉시 검증하는 도구 (예약됐는데 안 울리는 문제 자가진단)
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  icon: const Icon(Icons.notifications_active),
                  label: const Text('1분 후 테스트 알람 울리기'),
                  onPressed: () async {
                    Navigator.pop(ctx);
                    try {
                      await NotificationService.scheduleTestAlarm();
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                            content: Text('1분 뒤 테스트 알람이 옵니다 — 화면을 꺼두세요')));
                      }
                    } catch (e) {
                      if (mounted) {
                        ScaffoldMessenger.of(context)
                            .showSnackBar(SnackBar(content: Text('예약 실패: $e')));
                      }
                    }
                  },
                ),
              ),
              if (!canExactNow)
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.alarm_on),
                    label: const Text('정확 알람 허용하기 (설정 열림)'),
                    onPressed: () async {
                      Navigator.pop(ctx);
                      await NotificationService.requestExact();
                      final f = _feed;
                      if (f != null) {
                        try {
                          await widget.onFeedLoaded?.call(f); // 새 모드로 재예약
                        } catch (_) {}
                      }
                    },
                  ),
                ),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.restart_alt),
                  label: const Text('알람 다시 예약하기'),
                  onPressed: () async {
                    Navigator.pop(ctx);
                    final f = _feed;
                    if (f != null) {
                      try {
                        await widget.onFeedLoaded?.call(f);
                      } catch (_) {}
                    }
                    if (mounted) _showDiagnostics();
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('강좌 알리미'),
          actions: [
            IconButton(
              tooltip: '문화센터 바로가기',
              onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const CultureCentersScreen())),
              icon: const Icon(Icons.storefront_outlined),
            ),
            IconButton(onPressed: _showDiagnostics, icon: const Icon(Icons.info_outline)),
            IconButton(onPressed: _refresh, icon: const Icon(Icons.refresh)),
            IconButton(
              onPressed: _feed == null ? null : _openFilter,
              icon: Badge(
                isLabelVisible: !_sub.isEmpty,
                child: const Icon(Icons.tune),
              ),
            ),
          ],
          bottom: const TabBar(tabs: [
            Tab(text: '접수중'),
            Tab(text: '오픈예정'),
            Tab(text: '새소식'),
          ]),
        ),
        body: _body(),
      ),
    );
  }

  Widget _body() {
    if (_error != null && _feed == null) {
      // _error가 문자열(버전 안내 등)이면 그대로, 아니면 기본 네트워크 메시지
      final msg = _error is String
          ? _error as String
          : '데이터를 불러오지 못했어요.\n네트워크 연결을 확인해 주세요.';
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.cloud_off, size: 48),
          const SizedBox(height: 12),
          Text(msg, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          FilledButton(onPressed: _refresh, child: const Text('다시 시도')),
        ]),
      );
    }
    final feed = _feed;
    if (feed == null) return const Center(child: CircularProgressIndicator());

    // feed의 분류는 서버 생성 시점 기준 → 기기 시각으로 실시간 재분류
    // (오픈 지난 항목은 오픈예정에서 제거하고, 접수기간 시작된 '안내중'은 접수중으로)
    final now = (widget.clock ?? kstNow)();
    final open = filterCourses(feed.courses.where((c) => c.effectivelyOpen(now)).toList(), _sub);
    final byId = {for (final c in feed.courses) c.id: c};
    final upcoming = feed.upcoming.where((u) {
      final openAt = u.openAtDt;
      if (openAt == null || !openAt.isAfter(now)) return false; // 이미 오픈 → 예정에서 제거
      final c = byId[u.id];
      return c == null || matches(c, _sub);
    }).toList();

    return Column(
      children: [
        // 알림 초기화 실패 진단 배너 (앱은 계속 사용 가능)
        if (widget.initError != null)
          ValueListenableBuilder<String?>(
            valueListenable: widget.initError!,
            builder: (ctx, err, _) => err == null
                ? const SizedBox.shrink()
                : Container(
                    width: double.infinity,
                    color: Theme.of(ctx).colorScheme.errorContainer,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    child: Text('⚠️ $err', maxLines: 3, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11)),
                  ),
          ),
        if (_fromCache)
          Container(
            width: double.infinity,
            color: Theme.of(context).colorScheme.tertiaryContainer,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Text('오프라인 — 마지막 데이터(${feed.generatedAt})를 보여드려요',
                style: const TextStyle(fontSize: 12)),
          ),
        Expanded(
          child: TabBarView(children: [
            _courseList(open, empty: '조건에 맞는 접수중 강좌가 없어요'),
            _upcomingList(upcoming, byId, now), // now 공유 — 필터/표시 시각 불일치 방지
            _newsList(feed, byId),
          ]),
        ),
      ],
    );
  }

  Widget _courseList(List<Course> list, {required String empty}) {
    if (list.isEmpty) return Center(child: Text(empty));
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView.builder(
        itemCount: list.length,
        itemBuilder: (_, i) => CourseCard(course: list[i]),
      ),
    );
  }

  Widget _upcomingList(List<UpcomingOpening> ups, Map<String, Course> byId, DateTime now) {
    if (ups.isEmpty) return const Center(child: Text('조건에 맞는 오픈 예정 강좌가 없어요'));
    return ListView.builder(
      itemCount: ups.length,
      itemBuilder: (_, i) {
        final u = ups[i];
        final c = byId[u.id];
        return ListTile(
          leading: const Icon(Icons.alarm),
          title: Text(u.name, maxLines: 2, overflow: TextOverflow.ellipsis),
          subtitle: Text('${u.area.isEmpty ? '서울전역' : u.area} · ${u.openAt} 접수 시작'),
          trailing: Text(leadLabel(u.openAtDt, now), style: const TextStyle(fontWeight: FontWeight.w600)),
          onTap: c == null
              ? null
              : () => showModalBottomSheet(
                  context: context, showDragHandle: true, builder: (_) => _quickDetail(c)),
        );
      },
    );
  }

  Widget _newsList(Feed feed, Map<String, Course> byId) {
    final items = <Widget>[];
    final newFiltered = feed.newCourses.where((n) {
      final c = byId[n.id];
      return c == null || matches(c, _sub);
    }).toList();
    final reopenFiltered = feed.reopened.where((r) {
      final c = byId[r.id];
      return c == null || matches(c, _sub);
    }).toList();

    if (newFiltered.isNotEmpty) {
      items.add(_sectionHeader('🆕 새로 올라온 강좌 (48시간)'));
      items.addAll(newFiltered.map((n) => ListTile(
            dense: true,
            title: Text(n.name, maxLines: 2, overflow: TextOverflow.ellipsis),
            subtitle: Text('${n.area.isEmpty ? '서울전역' : n.area} · ${n.seenAt}'),
            onTap: byId[n.id] == null
                ? null
                : () => showModalBottomSheet(
                    context: context, showDragHandle: true, builder: (_) => _quickDetail(byId[n.id]!)),
          )));
    }
    if (reopenFiltered.isNotEmpty) {
      items.add(_sectionHeader('🔓 다시 열린 강좌 (7일)'));
      items.addAll(reopenFiltered.map((r) => ListTile(
            dense: true,
            title: Text(r.name, maxLines: 2, overflow: TextOverflow.ellipsis),
            subtitle: Text('${r.area.isEmpty ? '서울전역' : r.area} · ${r.at}'),
            onTap: byId[r.id] == null
                ? null
                : () => showModalBottomSheet(
                    context: context, showDragHandle: true, builder: (_) => _quickDetail(byId[r.id]!)),
          )));
    }
    if (items.isEmpty) return const Center(child: Text('새 소식이 없어요'));
    return ListView(children: items);
  }

  Widget _sectionHeader(String t) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: Text(t, style: const TextStyle(fontWeight: FontWeight.w700)),
      );

  Widget _quickDetail(Course c) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: CourseCard(course: c),
        ),
      );
}
