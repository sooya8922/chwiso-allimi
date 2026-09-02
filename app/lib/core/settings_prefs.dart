/// 앱 공용 설정 저장소 — 조용시간(두 도메인 공유) + 주말 다이제스트 on/off(나들이).
/// 키는 기존과 동일(quiet_config_v1 / digest_enabled_v1) → 도메인 background가 읽는 값과 일치.
/// (통합 전엔 각 도메인 PrefsService/필터시트에 흩어져 있던 설정을 '설정' 탭 한 곳으로 모음)
library;

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'time.dart';

class SettingsPrefs {
  static const _quietKey = 'quiet_config_v1'; // 강좌·나들이 공유
  static const _digestOnKey = 'digest_enabled_v1'; // 나들이 다이제스트

  Future<QuietConfig> loadQuiet() async {
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getString(_quietKey);
    if (raw == null) return const QuietConfig();
    try {
      return QuietConfig.fromJson(json.decode(raw) as Map<String, dynamic>);
    } catch (_) {
      return const QuietConfig(); // 파손 시 기본값
    }
  }

  Future<void> saveQuiet(QuietConfig q) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_quietKey, json.encode(q.toJson()));
  }

  Future<bool> loadDigestEnabled() async {
    final sp = await SharedPreferences.getInstance();
    return sp.getBool(_digestOnKey) ?? true;
  }

  Future<void> saveDigestEnabled(bool v) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setBool(_digestOnKey, v);
  }
}
