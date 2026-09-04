// 지도 URL 후보 목록 테스트 — 카카오맵→네이버맵→구글지도 우선순위 + 각 URL 형식.
// 앱 스킴은 canLaunchUrl로 설치 판정 후 실행되므로 오류 화면 없이 조용히 폴백된다(실기기 제보 반영).
import 'package:flutter_test/flutter_test.dart';
import 'package:yeollim_allim/widgets/course_card.dart';

void main() {
  group('buildMapCandidates', () {
    final c = buildMapCandidates(126.9, 37.5); // lng, lat

    test('우선순위: 카카오 → 네이버 → 구글(3개)', () {
      expect(c.length, 3);
      expect(c[0], startsWith('kakaomap://'));
      expect(c[1], startsWith('nmap://'));
      expect(c[2], startsWith('https://www.google.com/maps'));
    });

    test('카카오맵: 위도,경도 순', () {
      expect(c[0], 'kakaomap://look?p=37.5,126.9');
    });

    test('네이버지도: place + lat/lng + appname 필수(공식 형식)', () {
      expect(c[1], startsWith('nmap://place?'));
      expect(c[1], contains('lat=37.5'));
      expect(c[1], contains('lng=126.9'));
      expect(c[1], contains('appname='), reason: 'appname 없으면 네이버앱이 무시');
    });

    test('구글지도 웹: 최종 폴백(항상 열림)', () {
      expect(c[2], 'https://www.google.com/maps/search/?api=1&query=37.5,126.9');
    });

    test('모든 후보가 파싱 가능한 유효 URI', () {
      for (final u in c) {
        expect(() => Uri.parse(u), returnsNormally, reason: u);
      }
    });

    test('좌표만 사용 → 이름 특수문자로 깨질 여지 없음(문제였던 실좌표로도)', () {
      final r = buildMapCandidates(127.05775790548498, 37.55734277961993);
      for (final u in r) {
        expect(() => Uri.parse(u), returnsNormally);
      }
    });

    test('엣지: 음수 좌표(해외)·0 좌표에도 URL 유효', () {
      for (final r in [buildMapCandidates(-122.4, 37.7), buildMapCandidates(0, 0)]) {
        expect(r.length, 3);
        for (final u in r) {
          expect(() => Uri.parse(u), returnsNormally);
        }
      }
    });

    test('엣지: 앱 스킴 2개 + 웹 1개 구조 불변(폴백 순서 보장)', () {
      final r = buildMapCandidates(126.9, 37.5);
      // 앞 2개는 커스텀 스킴(canLaunchUrl 판정 대상), 마지막은 http(항상 열림)
      expect(Uri.parse(r[0]).scheme, 'kakaomap');
      expect(Uri.parse(r[1]).scheme, 'nmap');
      expect(Uri.parse(r[2]).scheme, 'https');
    });

    test('네이버 좌표 파라미터가 위도/경도 정확히 매핑(뒤바뀜 방지)', () {
      final r = buildMapCandidates(126.977, 37.566); // 서울시청 경도,위도
      final naver = Uri.parse(r[1]);
      expect(naver.queryParameters['lat'], '37.566');
      expect(naver.queryParameters['lng'], '126.977');
    });

    test('카카오 p= 파라미터가 위도,경도 순(뒤바뀜 방지)', () {
      final r = buildMapCandidates(126.977, 37.566);
      expect(r[0], 'kakaomap://look?p=37.566,126.977');
    });
  });

  group('buildRouteCandidates (길 찾기)', () {
    final r = buildRouteCandidates(126.9, 37.5, '서울시청 강좌');

    test('우선순위: 카카오 → 네이버 → 구글(3개)', () {
      expect(r.length, 3);
      expect(r[0], startsWith('kakaomap://route'));
      expect(r[1], startsWith('nmap://route/public'));
      expect(r[2], startsWith('https://www.google.com/maps/dir'));
    });

    test('카카오 대중교통 경로: 도착지 위도,경도 + PUBLICTRANSIT', () {
      expect(r[0], 'kakaomap://route?ep=37.5,126.9&by=PUBLICTRANSIT');
    });

    test('네이버 대중교통: dlat/dlng + 인코딩된 도착지명 + appname(현재 패키지)', () {
      final n = Uri.parse(r[1]);
      expect(n.queryParameters['dlat'], '37.5');
      expect(n.queryParameters['dlng'], '126.9');
      expect(n.queryParameters['dname'], '서울시청 강좌'); // 디코드되면 원문
      expect(n.queryParameters['appname'], 'com.sooya8922.yeollim');
    });

    test('구글 웹: 대중교통 길찾기 최종 폴백', () {
      expect(r[2], 'https://www.google.com/maps/dir/?api=1&destination=37.5,126.9&travelmode=transit');
    });

    test('이름 특수문자/빈값에도 URL 유효(파싱 가능)', () {
      for (final cand in [
        buildRouteCandidates(126.9, 37.5, '아이 & 가족 (무료)'),
        buildRouteCandidates(126.9, 37.5, ''),
      ]) {
        for (final u in cand) {
          expect(() => Uri.parse(u), returnsNormally, reason: u);
        }
      }
    });

    test('빈 이름이면 기본 도착지명으로 대체', () {
      final e = Uri.parse(buildRouteCandidates(126.9, 37.5, '')[1]);
      expect(e.queryParameters['dname'], '강좌 장소');
    });
  });
}
