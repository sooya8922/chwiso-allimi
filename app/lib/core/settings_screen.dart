/// 설정 탭 — 알림 동작 설정을 한 곳에 모음(통합).
///  - 조용시간(강좌·나들이 공유): 이 시간엔 즉시 알림을 아침으로 미룸. ⏰ 강좌 접수 알람은 예외 선택.
///  - 주말 다이제스트(나들이): 목·금 저녁 요약 on/off.
///
/// 저장은 즉시(토글마다). 조용시간 변경은 알람 재계획에 영향을 주므로 저장 후 재적용(best-effort).
/// prefs/onApply는 테스트에서 네트워크·플러그인 비의존으로 주입 가능.
library;

import 'package:flutter/material.dart';

import 'background.dart' show refreshAllAndNotify;
import 'settings_prefs.dart';
import 'time.dart';

class SettingsScreen extends StatefulWidget {
  final SettingsPrefs? prefs;

  /// 저장 후 재적용 훅(기본 = 두 도메인 갱신 → 알람 재계획). 테스트에서 no-op 주입.
  final Future<void> Function()? onApply;

  const SettingsScreen({super.key, this.prefs, this.onApply});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final SettingsPrefs _prefs = widget.prefs ?? SettingsPrefs();

  QuietConfig _quiet = const QuietConfig();
  bool _digestOn = true;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    // 저장소 오류여도 기본값으로 렌더(무한 로딩 방지 — chwiso 원칙).
    try {
      _quiet = await _prefs.loadQuiet();
      _digestOn = await _prefs.loadDigestEnabled();
    } catch (_) {/* 기본값 사용 */}
    if (mounted) setState(() => _loaded = true);
  }

  /// 조용시간 저장 후 재적용(알람 재계획). 저장/재적용 실패는 삼킨다(화면은 정상).
  Future<void> _saveQuiet(QuietConfig q) async {
    setState(() => _quiet = q);
    try {
      await _prefs.saveQuiet(q);
    } catch (_) {
      _saveFailedSnack();
      return;
    }
    try {
      await (widget.onApply ?? refreshAllAndNotify)();
    } catch (_) {/* 다음 새로고침 때 반영됨 */}
  }

  Future<void> _saveDigest(bool v) async {
    setState(() => _digestOn = v);
    try {
      await _prefs.saveDigestEnabled(v);
    } catch (_) {
      _saveFailedSnack();
    }
    // 다이제스트는 다음 발송 창에서 새 값이 반영되므로 즉시 재적용 불필요.
  }

  void _saveFailedSnack() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('설정 저장 실패 — 앱 재시작 시 이전 설정으로 돌아갈 수 있어요')));
  }

  Widget _hourDropdown(int value, ValueChanged<int?> onChanged) => DropdownButton<int>(
        value: value,
        isDense: true,
        items: List.generate(24, (h) => DropdownMenuItem(value: h, child: Text('$h시'))),
        onChanged: _quiet.enabled ? onChanged : null,
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('설정')),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Text('알림 시간대', style: Theme.of(context).textTheme.titleMedium),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('조용시간 사용'),
                  subtitle: const Text('이 시간엔 새 강좌·행사 알림을 아침으로 미뤄요', style: TextStyle(fontSize: 12)),
                  value: _quiet.enabled,
                  onChanged: (v) => _saveQuiet(_quiet.copyWith(enabled: v)),
                ),
                Row(
                  children: [
                    const SizedBox(width: 8),
                    _hourDropdown(_quiet.startHour, (v) => _saveQuiet(_quiet.copyWith(startHour: v))),
                    const Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Text('부터')),
                    _hourDropdown(_quiet.endHour, (v) => _saveQuiet(_quiet.copyWith(endHour: v))),
                    const Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Text('까지')),
                  ],
                ),
                // start==end면 조용시간이 실제로 적용 안 됨 — 사용자가 오해하지 않게 경고
                if (_quiet.enabled && _quiet.startHour == _quiet.endHour)
                  Padding(
                    padding: const EdgeInsets.only(left: 8, top: 4),
                    child: Text('같은 시간이라 조용시간이 적용되지 않아요',
                        style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.error)),
                  ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('조용시간에도 ⏰ 접수 알람은 울리기'),
                  subtitle: const Text('끄면 조용시간에 걸린 강좌 접수 알람은 예약하지 않아요', style: TextStyle(fontSize: 12)),
                  value: _quiet.alarmsExempt,
                  onChanged: _quiet.enabled ? (v) => _saveQuiet(_quiet.copyWith(alarmsExempt: v)) : null,
                ),
                const Divider(height: 32),
                Text('나들이', style: Theme.of(context).textTheme.titleMedium),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('🧺 주말 다이제스트'),
                  subtitle: const Text('목·금 저녁, 이번 주말 갈 만한 곳 요약을 한 번 보내드려요', style: TextStyle(fontSize: 12)),
                  value: _digestOn,
                  onChanged: _saveDigest,
                ),
                const Divider(height: 32),
                const ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text('강좌·나들이 알리미'),
                  subtitle: Text('서울 공공강좌 접수 알림 + 수도권 아이 나들이 행사 알림\n'
                      '회원가입 없음 · 개인정보 수집 없음 · 광고 없음'),
                ),
              ],
            ),
    );
  }
}
