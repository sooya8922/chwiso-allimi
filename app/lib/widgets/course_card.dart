import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/course.dart';

/// 지도 열기 후보 URL 목록(순수 함수, 테스트 대상). 우선순위: 카카오맵 → 네이버맵 → 구글지도(웹).
/// 앞의 두 개는 '앱 스킴'이라 canLaunchUrl로 설치 여부를 먼저 판정 → 없으면 실행 안 하고 다음으로
/// 조용히 폴백(에러 화면 안 뜸). 마지막 구글 웹은 항상 열리는 최종 안전망.
/// 좌표만 사용하고 이름은 안 넣어 특수문자로 URL이 깨질 여지도 없앤다.
List<String> buildMapCandidates(double lng, double lat) {
  return [
    // 카카오맵: look?p=위도,경도 (공식 문서 확인)
    'kakaomap://look?p=$lat,$lng',
    // 네이버지도: place로 마커 표시. appname 필수(없으면 앱이 무시), zoom이 아니라 level.
    'nmap://place?lat=$lat&lng=$lng&name=%EA%B0%95%EC%A2%8C%20%EC%9C%84%EC%B9%98&appname=com.sooya8922.yeollim',
    // 구글지도 웹(최종 폴백, 항상 열림)
    'https://www.google.com/maps/search/?api=1&query=$lat,$lng',
  ];
}

/// 대중교통 길찾기 후보 URL 목록(순수 함수). 우선순위는 위치 보기와 동일(카카오→네이버→구글 웹).
/// 나들이 알리미와 동일한 UX — 강좌 장소까지 대중교통 경로를 바로 연다.
/// 네이버는 도착지 이름이 필수라 인코딩해 넣는다(특수문자는 encodeQueryComponent가 처리).
List<String> buildRouteCandidates(double lng, double lat, String name) {
  final n = Uri.encodeQueryComponent(name.isEmpty ? '강좌 장소' : name);
  return [
    'kakaomap://route?ep=$lat,$lng&by=PUBLICTRANSIT',
    'nmap://route/public?dlat=$lat&dlng=$lng&dname=$n&appname=com.sooya8922.yeollim',
    'https://www.google.com/maps/dir/?api=1&destination=$lat,$lng&travelmode=transit',
  ];
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
              // 위치 보기 + 길 찾기 — 좌표 있는 강좌만(약 98%). 나들이 알리미와 동일 UX.
              if (course.hasLocation) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.place_outlined),
                        label: const Text('위치 보기'),
                        onPressed: () => _openMap(ctx, course),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.directions_transit),
                        label: const Text('길 찾기'),
                        onPressed: () => _openRoute(ctx, course),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// 좌표를 지도로 연다. 카카오맵→네이버맵→구글지도 순서로, 앱 스킴은 설치돼 있을 때만 실행.
  /// 각 시도를 try-catch로 감싸 canLaunchUrl/launchUrl이 예외를 던져도(앱 업데이트 중 등)
  /// 조용히 다음 후보로 폴백한다 — 이게 없으면 카카오맵 있는데 실행 실패 시 무반응(지난 오류).
  Future<void> _openMap(BuildContext context, Course c) async {
    final lat = c.y!, lng = c.x!; // yeyak: X=경도, Y=위도 (hasLocation 가드로 non-null 보장)
    await _launchFirst(context, buildMapCandidates(lng, lat), '지도 앱을 열 수 없어요');
  }

  Future<void> _openRoute(BuildContext context, Course c) async {
    final lat = c.y!, lng = c.x!;
    await _launchFirst(context, buildRouteCandidates(lng, lat, c.name), '길찾기 앱을 열 수 없어요');
  }

  /// 후보 URL을 순서대로 시도(카카오맵→네이버맵→구글 웹). 앱 스킴은 설치돼 있을 때만 실행,
  /// 각 시도를 try-catch로 감싸 예외를 던져도 조용히 다음 후보로 폴백 — 이게 없으면 카카오맵
  /// 있는데 실행 실패 시 무반응(지난 오류). 세 후보 전부 실패 시에만 사용자에게 스낵바.
  Future<void> _launchFirst(BuildContext context, List<String> candidates, String failMsg) async {
    for (var i = 0; i < candidates.length; i++) {
      final uri = Uri.parse(candidates[i]);
      final isLast = i == candidates.length - 1;
      try {
        // 마지막(구글 웹)은 항상 열리므로 판정 없이 실행. 앞의 앱 스킴은 설치 확인 후에만.
        if (isLast || await canLaunchUrl(uri)) {
          if (await launchUrl(uri, mode: LaunchMode.externalApplication)) return;
        }
      } catch (_) {
        // 이 후보 실패 → 다음 후보로 (조용히)
      }
    }
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(failMsg)));
    }
  }
}
