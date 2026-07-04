import 'package:flutter/material.dart';

import '../logic/matcher.dart';

/// 구독조건 편집 바텀시트. 저장은 호출측(HomeScreen)이 한다.
class FilterSheet extends StatefulWidget {
  final Subscription initial;
  final List<String> availableAreas; // feed에서 추출한 실제 구 목록

  const FilterSheet({super.key, required this.initial, required this.availableAreas});

  @override
  State<FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<FilterSheet> {
  late Set<String> areas = {...widget.initial.areas};
  late bool freeOnly = widget.initial.freeOnly;
  late Set<String> targets = {...widget.initial.targets};
  late final TextEditingController kwCtrl =
      TextEditingController(text: widget.initial.keywords.join(', '));

  static const targetLabels = {'kids': '어린이·가족', 'adult': '성인', 'senior': '시니어'};

  @override
  void dispose() {
    kwCtrl.dispose();
    super.dispose();
  }

  Subscription _build() => Subscription(
        areas: areas,
        freeOnly: freeOnly,
        targets: targets,
        keywords: kwCtrl.text
            .split(RegExp(r'[,\s]+'))
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .toList(),
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
                      hintText: '예: 방학, 원예, 목공', border: OutlineInputBorder(), isDense: true),
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
