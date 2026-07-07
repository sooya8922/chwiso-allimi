import 'package:flutter/material.dart';

import '../logic/matcher.dart';
import '../logic/notif_planner.dart';

/// 필터 시트 결과 — 구독조건 + 조용시간 설정
typedef FilterResult = ({Subscription sub, QuietConfig quiet});

/// 구독조건 편집 바텀시트. 저장은 호출측(HomeScreen)이 한다.
class FilterSheet extends StatefulWidget {
  final Subscription initial;
  final QuietConfig initialQuiet;
  final List<String> availableAreas; // feed에서 추출한 실제 구 목록

  const FilterSheet(
      {super.key, required this.initial, this.initialQuiet = const QuietConfig(), required this.availableAreas});

  @override
  State<FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<FilterSheet> {
  // 현재 feed에 없는 저장된 지역은 칩이 안 그려져 보이지도/해제도 못 함(유령 필터) → 교집합만 유지.
  late Set<String> areas = widget.initial.areas.intersection(widget.availableAreas.toSet());
  late bool freeOnly = widget.initial.freeOnly;
  late Set<String> targets = {...widget.initial.targets};
  late QuietConfig quiet = widget.initialQuiet;
  late final TextEditingController kwCtrl =
      TextEditingController(text: widget.initial.keywords.join(', '));

  static const targetLabels = {'kids': '어린이·가족', 'adult': '성인', 'senior': '시니어'};

  @override
  void dispose() {
    kwCtrl.dispose();
    super.dispose();
  }

  FilterResult _build() => (
        sub: Subscription(
          areas: areas,
          freeOnly: freeOnly,
          targets: targets,
          keywords: kwCtrl.text
              .split(RegExp(r'[,\s]+'))
              .map((s) => s.trim())
              .where((s) => s.isNotEmpty)
              .toList(),
        ),
        quiet: quiet,
      );

  Widget _hourDropdown(int value, ValueChanged<int?> onChanged) => DropdownButton<int>(
        value: value,
        isDense: true,
        items: List.generate(24, (h) => DropdownMenuItem(value: h, child: Text('$h시'))),
        onChanged: quiet.enabled ? onChanged : null,
      );

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      builder: (ctx, scroll) => Column(
        children: [
          Expanded(
            child: ListView(
              controller: scroll,
              padding: const EdgeInsets.all(20),
              children: [
                Text('알림 조건', style: Theme.of(ctx).textTheme.titleLarge),
                const SizedBox(height: 4),
                Text('조건에 맞는 강좌가 새로 열리면 알려드려요. 비워두면 전체.',
                    style: TextStyle(fontSize: 13, color: Theme.of(ctx).colorScheme.onSurfaceVariant)),
                const SizedBox(height: 16),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('무료만'),
                  value: freeOnly,
                  onChanged: (v) => setState(() => freeOnly = v),
                ),
                const SizedBox(height: 8),
                const Text('대상', style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: targetLabels.entries
                      .map((e) => FilterChip(
                            label: Text(e.value),
                            selected: targets.contains(e.key),
                            onSelected: (v) =>
                                setState(() => v ? targets.add(e.key) : targets.remove(e.key)),
                          ))
                      .toList(),
                ),
                const SizedBox(height: 16),
                const Text('키워드 (쉼표로 구분)', style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                TextField(
                  controller: kwCtrl,
                  decoration: const InputDecoration(
                      hintText: '예: 방학 원예 목공 (쉼표·띄어쓰기로 구분)', border: OutlineInputBorder(), isDense: true),
                ),
                const SizedBox(height: 16),
                Text('지역 (${areas.isEmpty ? '전체' : '${areas.length}개'})',
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: widget.availableAreas
                      .map((a) => FilterChip(
                            label: Text(a, style: const TextStyle(fontSize: 12)),
                            selected: areas.contains(a),
                            onSelected: (v) => setState(() => v ? areas.add(a) : areas.remove(a)),
                          ))
                      .toList(),
                ),
                const Divider(height: 32),
                const Text('알림 시간대', style: TextStyle(fontWeight: FontWeight.w600)),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('조용시간 사용'),
                  subtitle: const Text('이 시간엔 새 강좌·재오픈 알림을 아침으로 미뤄요', style: TextStyle(fontSize: 12)),
                  value: quiet.enabled,
                  onChanged: (v) => setState(() => quiet = quiet.copyWith(enabled: v)),
                ),
                Row(
                  children: [
                    const SizedBox(width: 8),
                    _hourDropdown(quiet.startHour, (v) => setState(() => quiet = quiet.copyWith(startHour: v))),
                    const Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Text('부터')),
                    _hourDropdown(quiet.endHour, (v) => setState(() => quiet = quiet.copyWith(endHour: v))),
                    const Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Text('까지')),
                  ],
                ),
                // start==end면 조용시간이 실제로 적용 안 됨 — 사용자가 오해하지 않게 경고
                if (quiet.enabled && quiet.startHour == quiet.endHour)
                  Padding(
                    padding: const EdgeInsets.only(left: 8, top: 4),
                    child: Text('같은 시간이라 조용시간이 적용되지 않아요',
                        style: TextStyle(fontSize: 12, color: Theme.of(ctx).colorScheme.error)),
                  ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('조용시간에도 ⏰ 접수 알람은 울리기'),
                  subtitle: const Text('끄면 조용시간에 걸린 접수 알람은 예약하지 않아요', style: TextStyle(fontSize: 12)),
                  value: quiet.alarmsExempt,
                  onChanged: quiet.enabled
                      ? (v) => setState(() => quiet = quiet.copyWith(alarmsExempt: v))
                      : null,
                ),
              ],
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: Row(
                children: [
                  TextButton(
                    onPressed: () => setState(() {
                      areas.clear();
                      targets.clear();
                      freeOnly = false;
                      kwCtrl.clear();
                      quiet = const QuietConfig();
                    }),
                    child: const Text('초기화'),
                  ),
                  const Spacer(),
                  FilledButton(
                    onPressed: () => Navigator.pop(context, _build()),
                    child: const Text('적용'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
