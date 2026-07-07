// FeedService 캐시/폴백 로직 테스트 — 오프라인·에러·파손 등 IO 엣지(커버리지 0%였던 영역).
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:yeollim_allim/services/feed_service.dart';

const _validFeed = '{"version":1,"generated_at":"2026-07-07 10:00","sources":["seoul_public"],'
    '"counts":{},"courses":[{"id":"S1","name":"강좌","area":"마포구","status":"접수중"}],'
    '"new":[],"reopened":[],"upcoming":[]}';

void main() {
  late Directory tmp;
  late File cache;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('feedtest');
    cache = File('${tmp.path}/feed_cache.json');
  });
  tearDown(() async => tmp.existsSync() ? await tmp.delete(recursive: true) : null);

  FeedService svc(http.Client c) => FeedService(client: c, cacheFile: cache);

  test('네트워크 200 → 파싱 성공 + 캐시 기록(fromCache=false)', () async {
    final s = svc(MockClient((_) async => http.Response.bytes(utf8.encode(_validFeed), 200)));
    final r = await s.load();
    expect(r.fromCache, false);
    expect(r.feed.courses.first.name, '강좌');
    expect(await cache.exists(), true, reason: '성공 응답은 캐시에 기록');
  });

  test('오프라인(예외) + 캐시 있음 → 캐시 폴백(fromCache=true)', () async {
    await cache.writeAsString(_validFeed); // 이전 성공분
    final s = svc(MockClient((_) async => throw const SocketException('offline')));
    final r = await s.load();
    expect(r.fromCache, true);
    expect(r.feed.courses.first.name, '강좌');
  });

  test('오프라인 + 캐시 없음 → 예외 재전파(첫 실행+오프라인)', () async {
    final s = svc(MockClient((_) async => throw const SocketException('offline')));
    expect(() => s.load(), throwsA(isA<SocketException>()));
  });

  test('HTTP 404 + 캐시 있음 → 캐시 폴백', () async {
    await cache.writeAsString(_validFeed);
    final s = svc(MockClient((_) async => http.Response('not found', 404)));
    final r = await s.load();
    expect(r.fromCache, true);
  });

  test('엣지: 200이지만 파손 JSON + 캐시 있음 → 마지막 정상 캐시로 폴백', () async {
    await cache.writeAsString(_validFeed);
    final s = svc(MockClient((_) async => http.Response.bytes(utf8.encode('{깨짐'), 200)));
    final r = await s.load();
    expect(r.fromCache, true, reason: '신선하지만 깨진 데이터보다 마지막 정상본');
  });

  test('엣지: 파손 캐시 → loadFromCache가 null(크래시 없음)', () async {
    await cache.writeAsString('{깨진 캐시');
    final s = svc(MockClient((_) async => throw const SocketException('x')));
    expect(() => s.load(), throwsA(isA<SocketException>()),
        reason: '캐시가 못 쓰면 네트워크 예외를 그대로 던짐');
    expect(await s.loadFromCache(), isNull);
  });

  test('엣지: UTF-8 한글 디코딩 (content-type 헤더 무관)', () async {
    final feed = _validFeed.replaceAll('강좌', '어린이 요리교실');
    final s = svc(MockClient((_) async => http.Response.bytes(utf8.encode(feed), 200)));
    final r = await s.load();
    expect(r.feed.courses.first.name, '어린이 요리교실');
  });

  test('엣지: 미래 version → 예외 후 캐시 폴백', () async {
    await cache.writeAsString(_validFeed);
    final future = _validFeed.replaceFirst('"version":1', '"version":2');
    final s = svc(MockClient((_) async => http.Response.bytes(utf8.encode(future), 200)));
    final r = await s.load();
    expect(r.fromCache, true, reason: '구버전 앱은 미래 feed 대신 캐시 사용');
  });
}
