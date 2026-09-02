// 오케스트레이터(refreshAllAndNotify) 도메인 실패 격리 검증.
// 실제 도메인 루틴 대신 주입 훅으로 성공/실패를 만들어, 한 도메인 실패가 다른 도메인을
// 막지 않는지(격리) + 반환 bool이 재시도 신호로 맞는지 검증한다.
import 'package:flutter_test/flutter_test.dart';
import 'package:yeollim_allim/core/background.dart';

void main() {
  test('둘 다 성공 → true, 둘 다 실행됨', () async {
    var c = false, e = false;
    final ok = await refreshAllAndNotify(
      courseRefresh: () async => c = true,
      eventRefresh: () async => e = true,
    );
    expect(ok, true);
    expect(c && e, true);
  });

  test('강좌 실패해도 나들이는 실행됨(격리), 반환 false', () async {
    var e = false;
    final ok = await refreshAllAndNotify(
      courseRefresh: () async => throw Exception('course down'),
      eventRefresh: () async => e = true,
    );
    expect(e, true, reason: '강좌 실패가 나들이를 막으면 안 됨');
    expect(ok, false, reason: '하나라도 실패면 재시도 신호(false)');
  });

  test('나들이 실패해도 강좌는 실행됨(격리), 반환 false', () async {
    var c = false;
    final ok = await refreshAllAndNotify(
      courseRefresh: () async => c = true,
      eventRefresh: () async => throw Exception('event down'),
    );
    expect(c, true, reason: '나들이 실패가 강좌를 막으면 안 됨');
    expect(ok, false);
  });

  test('둘 다 실패 → false, 크래시 없음', () async {
    final ok = await refreshAllAndNotify(
      courseRefresh: () async => throw Exception('c'),
      eventRefresh: () async => throw Exception('e'),
    );
    expect(ok, false);
  });
}
