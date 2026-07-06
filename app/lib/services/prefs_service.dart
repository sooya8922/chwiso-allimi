/// 구독조건 저장/로드 — shared_preferences. 개인정보는 기기 밖으로 나가지 않는다.
library;

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../logic/matcher.dart';
import '../logic/notif_planner.dart';

class PrefsService {
  static const _key = 'subscription_v1';
  static const _quietKey = 'quiet_config_v1';

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

  Future<Subscription> load() async {
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getString(_key);
    if (raw == null) return const Subscription();
    try {
      return Subscription.fromJson(json.decode(raw) as Map<String, dynamic>);
    } catch (_) {
      return const Subscription(); // 파손 시 초기화
    }
  }

  Future<void> save(Subscription s) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_key, json.encode(s.toJson()));
  }
}
