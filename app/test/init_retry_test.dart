import 'package:flutter_test/flutter_test.dart';

// NotificationService.init()의 실패-시-재시도 패턴을 동일 구조로 재현 검증.
// (실제 NotificationService는 플러그인 의존이라 단위테스트 불가 — 패턴만 고정)
class _InitPattern {
  Future<void>? _f;
  int attempts = 0;
  bool failNext;
  _InitPattern(this.failNext);
  Future<void> init() {
    return _f ??= _do().catchError((e) {
      _f = null; // 실패 시 캐시 비움 → 재시도 가능
      throw e;
    });
  }
  Future<void> _do() async {
    attempts++;
    if (failNext) { failNext = false; throw 'boom'; }
  }
}

void main() {
  test('성공 시 캐시 → 여러 번 불러도 _do 1회', () async {
    final p = _InitPattern(false);
    await p.init(); await p.init(); await p.init();
    expect(p.attempts, 1);
  });

  test('실패 시 캐시 비움 → 다음 호출이 재시도(영구 실패 방지)', () async {
    final p = _InitPattern(true); // 첫 시도 실패
    expect(() => p.init(), throwsA('boom'));
    await Future.delayed(Duration.zero); // catchError 처리 대기
    // 두 번째 호출은 성공해야
    await p.init();
    expect(p.attempts, 2, reason: '실패 후 재시도되어 총 2회');
  });

  test('동시 진입 여러개 — 성공 시 _do 1회만', () async {
    final p = _InitPattern(false);
    await Future.wait([p.init(), p.init(), p.init()]);
    expect(p.attempts, 1);
  });
}
