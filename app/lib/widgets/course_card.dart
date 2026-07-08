import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/course.dart';

/// 지도 URL(순수 함수, 테스트 대상). 구글지도 범용 검색 URL —
/// 좌표만 쓰고 이름은 안 넣어 어떤 특수문자(대괄호/슬래시/괄호)에도 안 깨진다.
/// 구글맵 앱 있으면 앱으로, 없으면 브라우저에서 핀 표시. 카카오식 "존재하지 않는 URL" 오류 불가.
String buildMapUrl(double lng, double lat) {
  return 'https://www.google.com/maps/search/?api=1&query=$lat,$lng';
}

/// 강좌 카드 — 리스트의 기본 단위.
class CourseCard extends StatelessWidget {
  final Course course;

  const CourseCard({super.key, required this.course});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      child: InkWell(
        onTap: () => _showDetail(context),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _thumb(cs),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(course.name,
                        maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    Wrap(spacing: 6, runSpacing: 4, children: [
                      _chip(course.areaLabel, cs.secondaryContainer, cs.onSecondaryContainer),
                      if (course.pay.isNotEmpty)
                        _chip(course.pay, course.isFree ? const Color(0xFFD7F0DF) : cs.surfaceContainerHighest,
                            course.isFree ? const Color(0xFF1B5E20) : cs.onSurfaceVariant),
                      if (course.cat.isNotEmpty) _chip(course.cat, cs.surfaceContainerHighest, cs.onSurfaceVariant),
                      _statusChip(course.status, cs),
                    ]),
                    if (course.rcptBgn.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text('접수 ${course.rcptBgn} ~ ${course.rcptEnd}',
                          style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _thumb(ColorScheme cs) => ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          width: 56,
          height: 56,
          // 이미지 URL이 깨져도 앱이 안 깨지게 (엣지: FileDown.do가 404/비이미지 응답 가능)
          child: course.img.isEmpty
              ? _thumbFallback(cs)
              : Image.network(course.img, fit: BoxFit.cover, errorBuilder: (_, __, ___) => _thumbFallback(cs)),
        ),
      );

  Widget _thumbFallback(ColorScheme cs) =>
      Container(color: cs.surfaceContainerHighest, child: Icon(Icons.school_outlined, color: cs.onSurfaceVariant));

  Widget _chip(String label, Color bg, Color fg) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
        child: Text(label, style: TextStyle(fontSize: 11, color: fg)),
      );

  Widget _statusChip(String status, ColorScheme cs) {
    final (bg, fg) = switch (status) {
      '접수중' => (const Color(0xFFD7F0DF), const Color(0xFF1B5E20)),
      '안내중' => (const Color(0xFFFFF3D6), const Color(0xFF7A5900)),
      _ => (cs.errorContainer, cs.onErrorContainer),
    };
    return _chip(status, bg, fg);
  }

  void _showDetail(BuildContext context) {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(course.name, style: Theme.of(ctx).textTheme.titleMedium),
              const SizedBox(height: 8),
              Text('${course.areaLabel} · ${course.cat}${course.pay.isNotEmpty ? ' · ${course.pay}' : ''}'),
              if (course.target.isNotEmpty) Text('대상: ${course.target}', style: const TextStyle(fontSize: 13)),
              if (course.rcptBgn.isNotEmpty)
                Text('접수기간: ${course.rcptBgn} ~ ${course.rcptEnd}', style: const TextStyle(fontSize: 13)),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  icon: const Icon(Icons.open_in_new),
                  label: const Text('예약 페이지 열기'),
                  onPressed: course.url.isEmpty
                      ? null
                      // 다중 도메인(yeyak/umppa 등)이라 항상 외부 브라우저로 (실측 근거)
                      : () => launchUrl(Uri.parse(course.url), mode: LaunchMode.externalApplication),
                ),
              ),
              // 위치 보기 — 좌표 있는 강좌만(약 98%). 온라인 예매지만 '갈 만한 거리인지' 판단 보조.
              if (course.hasLocation) ...[
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.place_outlined),
                    label: const Text('위치 보기'),
                    onPressed: () => _openMap(course),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// 좌표를 지도로 연다. 구글지도 범용 URL만 사용 — geo: 스킴(지도앱 없는 폰서 브라우저로
  /// 라우팅돼 "존재하지 않는 URL" 오류)도, 카카오 앱링크(앱이 딥링크를 웹과 다르게 처리해
  /// 오류 가능)도 피한다. 좌표만 넘겨 이름 특수문자로 깨질 여지도 없앰(실기기 반복 제보).
  Future<void> _openMap(Course c) async {
    final lat = c.y!, lng = c.x!; // yeyak: X=경도, Y=위도 (hasLocation 가드로 non-null 보장)
    await launchUrl(Uri.parse(buildMapUrl(lng, lat)), mode: LaunchMode.externalApplication);
  }
}
