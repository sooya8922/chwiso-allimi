import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yeollim_allim/logic/matcher.dart';
import 'package:yeollim_allim/logic/notif_planner.dart';
import 'package:yeollim_allim/models/course.dart';
import 'package:yeollim_allim/screens/home_screen.dart';
import 'package:yeollim_allim/services/feed_service.dart';
import 'package:yeollim_allim/services/prefs_service.dart';
import 'feed_parse_test.dart' show sampleFeed;

class CountingFeed extends FeedService {
  int n = 0;
  @override
  Future<({Feed feed, bool fromCache})> load() async {
    n++;
    return (feed: Feed.fromJson(json.decode(sampleFeed) as Map<String, dynamic>), fromCache: false);
  }
}
class FakePrefs extends PrefsService {
  @override Future<Subscription> load() async => const Subscription();
  @override Future<void> save(Subscription s) async {}
  @override Future<QuietConfig> loadQuiet() async => const QuietConfig();
  @override Future<void> saveQuiet(QuietConfig q) async {}
}

void main() {
  testWidgets('엣지: paused만(resume 없이)는 새로고침 안 함', (tester) async {
    final f = CountingFeed();
    await tester.pumpWidget(MaterialApp(home: HomeScreen(
      feedService: f, prefsService: FakePrefs(), clock: () => DateTime(2026,7,10,9,0))));
    await tester.pump(); await tester.pump();
    final base = f.n;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    expect(f.n, base, reason: 'paused는 트리거 아님');
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    expect(f.n, base, reason: 'inactive도 트리거 아님');
  });

  testWidgets('엣지: 연속 resume 여러번 — 3분 가드로 1회만', (tester) async {
    var clock = DateTime(2026,7,10,9,0);
    final f = CountingFeed();
    await tester.pumpWidget(MaterialApp(home: HomeScreen(
      feedService: f, prefsService: FakePrefs(), clock: () => clock)));
    await tester.pump(); await tester.pump();
    final base = f.n;
    // 같은 분에 resume 3번
    for (var i=0;i<3;i++){
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
    }
    expect(f.n, base, reason: '3분 내 연속 resume은 전부 스킵');
  });

  testWidgets('엣지: dispose 후 콜백 안전(옵저버 해제)', (tester) async {
    final f = CountingFeed();
    await tester.pumpWidget(MaterialApp(home: HomeScreen(
      feedService: f, prefsService: FakePrefs(), clock: () => DateTime(2026,7,10,9,0))));
    await tester.pump(); await tester.pump();
    // 위젯 제거 → dispose에서 옵저버 해제되어야, 이후 라이프사이클 이벤트가 죽은 state 안 건드림
    await tester.pumpWidget(const MaterialApp(home: Scaffold()));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(tester.takeException(), isNull, reason: 'dispose 후 콜백에 예외 없어야');
  });
}
