import 'package:flutter/material.dart';

import '../logic/matcher.dart';

/// 필터 시트 결과 — 구독조건만. (조용시간·다이제스트는 '설정' 탭으로 이동)
typedef FilterResult = ({Subscription sub});

/// 구독조건 편집 바텀시트. 저장은 호출측(HomeScreen)이 한다.
class FilterSheet extends StatefulWidget {
  final Subscription initial;

  const FilterSheet({super.key, required this.initial});

  @override
  State<FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<FilterSheet> {
  static const allAreas = ['서울', '경기', '인천'];

  late Set<String> areas = {...widget.initial.areas};
  late bool kidOnly = widget.initial.kidOnly;
  late bool freeOnly = widget.initial.freeOnly;
  late final TextEditingController kwCtrl =
      TextEditingController(text: widget.initial.keywords.join(', '));

  @override
  void dispose() {
    kwCtrl.dispose();
    super.dispose();
  }

  FilterResult _build() => (
        sub: Subscription(
          areas: areas,
          kidOnly: kidOnly,
          freeOnly: freeOnly,
          keywords: kwCtrl.text
              .split(RegExp(r'[,\s]+'))
              .map((s) => s.trim())
              .where((s) => s.isNotEmpty)
              .toList(),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      builder: (ctx, scroll) => Column(
        children: [
          Expanded(
            child: ListView(
              controller: scroll,
              padding: const EdgeInsets.all(20),
              children: [
                Text('보기·알림 조건', style: Theme.of(ctx).textTheme.titleLarge),
                const SizedBox(height: 4),
                Text('목록과 알림 모두에 적용돼요. 비워두면 전체.',
                    style: TextStyle(fontSize: 13, color: Theme.of(ctx).colorScheme.onSurfaceVariant)),
                const SizedBox(height: 12),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('아이 관련 행사만'),
                  subtitle: const Text('아동공연·가족행사 등만 보여요 (끄면 전체 행사)', style: TextStyle(fontSize: 12)),
                  value: kidOnly,
                  onChanged: (v) => setState(() => kidOnly = v),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('무료만'),
                  value: freeOnly,
                  onChanged: (v) => setState(() => freeOnly = v),
                ),
                const SizedBox(height: 8),
                Text('지역 (${areas.isEmpty ? '전체' : areas.join('·')})',
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: allAreas
                      .map((a) => FilterChip(
                            label: Text(a),
                            selected: areas.contains(a),
                            onSelected: (v) => setState(() => v ? areas.add(a) : areas.remove(a)),
                          ))
                      .toList(),
                ),
                const SizedBox(height: 16),
                const Text('키워드 (쉼표로 구분)', style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                TextField(
                  controller: kwCtrl,
                  decoration: const InputDecoration(
                      hintText: '예: 인형극 박물관 체험', border: OutlineInputBorder(), isDense: true),
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
                      kidOnly = true;
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
