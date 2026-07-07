// 홈 화면 위젯 테스트 — 페이크 서비스 주입(네트워크/플러그인 비의존).
// ① 성공 경로: 리스트/탭/필터 렌더 ② 실패 경로(오프라인 첫 실행): 오류 UI
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

class FakeFeedService extends FeedService {
  final bool fail;
  FakeFeedService({this.fail = false});

  @override
  Future<({Feed feed, bool fromCache})> load() async {
    if (fail) throw Exception('offline');
    return (feed: Feed.fromJson(json.decode(sampleFeed) as Map<String, dynamic>), fromCache: false);
  }
}

class FakePrefsService extends PrefsService {
  Subscription stored = const Subscription();
  QuietConfig storedQuiet = const QuietConfig();

  @override
  Future<Subscription> load() async => stored;

  @override
  Future<void> save(Subscription s) async => stored = s;

  @override
  Future<QuietConfig> loadQuiet() async => storedQuiet;

  @override
  Future<void> saveQuiet(QuietConfig q) async => storedQuiet = q;
}

Widget app({bool fail = false, DateTime? clock}) => MaterialApp(
      home: HomeScreen(
        feedService: FakeFeedService(fail: fail),
        prefsService: FakePrefsService(),
        clock: () => clock ?? DateTime(2026, 7, 4, 13, 0), // 고정 시계(테스트 결정성)
      ),
    );

void main() {
  testWidgets('성공 경로: 접수중 리스트에 강좌 카드 렌더', (tester) async {
    await tester.pumpWidget(app());
    await tester.pump(); // _init 완료
    await tester.pump();

    expect(find.text('열림알림'), findsOneWidget);
    // sampleFeed의 접수중 강좌(S1)가 보이고, 마감(S3)은 접수중 탭에 없음
    expect(find.textContaining('반딧불이 해설'), findsOneWidget);
    expect(find.textContaining('뜨개모자'), findsNothing);
  });

  testWidgets('오픈예정 탭: upcoming + 서울전역 표기(빈 area 엣지)', (tester) async {
    await tester.pumpWidget(app());
    await tester.pump();
    await tester.pump();

    await tester.tap(find.text('오픈예정'));
    await tester.pumpAndSettle();
    expect(find.textContaining('가드닝'), findsOneWidget);
    expect(find.textContaining('서울전역'), findsOneWidget);
  });

  testWidgets('새소식 탭: 신규+재오픈 섹션', (tester) async {
    await tester.pumpWidget(app());
    await tester.pump();
    await tester.pump();

    await tester.tap(find.text('새소식'));
    await tester.pumpAndSettle();
    expect(find.textContaining('새로 올라온 강좌'), findsOneWidget);
    expect(find.textContaining('다시 열린 강좌'), findsOneWidget);
  });

  testWidgets('실시간 재분류: 오픈 지난 강좌는 오픈예정에서 빠지고 접수중으로 (M4 넷마블 케이스)', (tester) async {
    // S2(가드닝): 안내중, rcpt_bgn=7/6 10:00, upcoming open_at=7/6 10:00.
    // 시계를 7/6 12:00으로 → 오픈예정에서 사라지고 접수중 탭에 나타나야 한다.
    await tester.pumpWidget(app(clock: DateTime(2026, 7, 6, 12, 0)));
    await tester.pump();
    await tester.pump();

    // 접수중 탭(기본): 가드닝이 '실질 오픈'으로 승격되어 보임
    expect(find.textContaining('가드닝'), findsOneWidget);

    await tester.tap(find.text('오픈예정'));
    await tester.pumpAndSettle();
    expect(find.textContaining('가드닝'), findsNothing, reason: '이미 오픈 → 예정 목록에서 제거');
  });

  testWidgets('실패 경로(오프라인 첫 실행): 크래시 없이 오류 UI + 다시 시도', (tester) async {
    await tester.pumpWidget(app(fail: true));
    await tester.pump();
    await tester.pump();

    expect(find.textContaining('불러오지 못했'), findsOneWidget);
    expect(find.text('다시 시도'), findsOneWidget);
  });
}
