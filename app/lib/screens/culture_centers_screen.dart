import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// 백화점·마트 문화센터 '바로가기' 화면.
/// 중요: 강좌 데이터를 수집·저장·표시하지 않는다. 각 사 공식 페이지로 여는 링크만 제공한다
/// (각 사 이용약관의 콘텐츠 재배포 금지를 피하기 위함 — 링크는 자유, 데이터 재공개는 위반).
class CultureCentersScreen extends StatelessWidget {
  const CultureCentersScreen({super.key});

  // 각 사 문화센터 공식 페이지(모바일). 링크만 — 데이터는 안 가져온다.
  static const _centers = <({String name, String desc, String url})>[
    (name: '홈플러스 문화센터', desc: '전국 홈플러스 지점 강좌', url: 'https://mschool.homeplus.co.kr/'),
    (name: '이마트 컬처클럽', desc: '이마트 문화센터 강좌', url: 'https://m.cultureclub.emart.com/main'),
    (name: '현대백화점 문화센터', desc: '현대백화점 지점별 강좌', url: 'https://www.ehyundai.com/mobile/culture/main.do'),
    (name: '롯데백화점 문화센터', desc: '롯데백화점 라이프스타일 강좌', url: 'https://culture.lotteshopping.com/index.do'),
    (name: '롯데마트 문화센터', desc: '롯데마트 문화센터 강좌', url: 'https://m.culture.lottemart.com/cu/gus/course/courseinfo/courselist.do'),
    (name: '신세계 아카데미', desc: '신세계백화점 문화 강좌', url: 'https://www.shinsegae.com/culture/academy/index.do'),
  ];

  Future<void> _open(String url) async {
    final uri = Uri.tryParse(url);
    if (uri != null) await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('문화센터 바로가기')),
      body: Column(
        children: [
          // 안내문(부드러운 톤): 공식 페이지로 이동, 신청은 각 사이트
          Container(
            width: double.infinity,
            color: cs.secondaryContainer,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Text(
              '각 문화센터 공식 페이지로 바로 이동합니다.\n강좌 확인과 신청은 각 사이트에서 진행돼요.',
              style: TextStyle(fontSize: 13, color: cs.onSecondaryContainer),
            ),
          ),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: _centers.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, i) {
                final c = _centers[i];
                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor: cs.surfaceContainerHighest,
                    child: Icon(Icons.storefront_outlined, color: cs.onSurfaceVariant),
                  ),
                  title: Text(c.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text(c.desc, style: const TextStyle(fontSize: 12)),
                  trailing: const Icon(Icons.open_in_new, size: 18),
                  onTap: () => _open(c.url),
                );
              },
            ),
          ),
          // 하단 면책문(딱딱하지만 안전): 데이터 미수집 명시
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Text(
                '본 서비스는 각 문화센터의 공식 페이지를 안내하며, 강좌 정보를 수집·제공하지 않습니다.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
