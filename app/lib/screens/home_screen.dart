import 'package:flutter/material.dart';

import '../logic/matcher.dart';
import '../models/course.dart';
import '../services/feed_service.dart';
import '../services/prefs_service.dart';
import '../widgets/course_card.dart';
import '../widgets/filter_sheet.dart';

/// 홈 — 탭 3개: 접수중 / 오픈예정 / 새소식(신규+재오픈)
/// 서비스는 주입 가능(테스트에서 페이크로 교체 — 네트워크/플러그인 비의존).
class HomeScreen extends StatefulWidget {
  final FeedService? feedService;
  final PrefsService? prefsService;

  const HomeScreen({super.key, this.feedService, this.prefsService});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final FeedService _feedSvc = widget.feedService ?? FeedService();
  late final PrefsService _prefsSvc = widget.prefsService ?? PrefsService();

  Feed? _feed;
  bool _fromCache = false;
  Object? _error;
  Subscription _sub = const Subscription();

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    _sub = await _prefsSvc.load();
    await _refresh();
  }

  Future<void> _refresh() async {
    setState(() => _error = null);
    try {
      final r = await _feedSvc.load();
      setState(() {
        _feed = r.feed;
        _fromCache = r.fromCache;
      });
    } catch (e) {
      setState(() => _error = e);
    }
  }

  List<String> get _areas {
    final s = (_feed?.courses ?? []).map((c) => c.area).where((a) => a.isNotEmpty).toSet().toList()..sort();
    return s;
  }

  Future<void> _openFilter() async {
    final result = await showModalBottomSheet<Subscription>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => FilterSheet(initial: _sub, availableAreas: _areas),
    );
    if (result != null) {
      setState(() => _sub = result);
      await _prefsSvc.save(result);
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('열림알림'),
          actions: [
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
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.cloud_off, size: 48),
          const SizedBox(height: 12),
          const Text('데이터를 불러오지 못했어요.\n네트워크 연결을 확인해 주세요.', textAlign: TextAlign.center),
          const SizedBox(height: 12),
          FilledButton(onPressed: _refresh, child: const Text('다시 시도')),
        ]),
      );
    }
    final feed = _feed;
    if (feed == null) return const Center(child: CircularProgressIndicator());

    final open = filterCourses(feed.courses.where((c) => c.isOpen).toList(), _sub);
    final byId = {for (final c in feed.courses) c.id: c};
    final upcoming = feed.upcoming.where((u) {
      final c = byId[u.id];
      return c == null || matches(c, _sub);
    }).toList();

    return Column(
      children: [
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
            _upcomingList(upcoming, byId),
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

  Widget _upcomingList(List<UpcomingOpening> ups, Map<String, Course> byId) {
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
          trailing: Text(_leadLabel(u.leadMin), style: const TextStyle(fontWeight: FontWeight.w600)),
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

  static String _leadLabel(int min) {
    if (min < 60) return '$min분 후';
    if (min < 1440) return '${(min / 60).round()}시간 후';
    return '${(min / 1440).round()}일 후';
  }
}
