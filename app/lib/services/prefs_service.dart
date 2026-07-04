/// 구독조건 저장/로드 — shared_preferences. 개인정보는 기기 밖으로 나가지 않는다.
library;

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../logic/matcher.dart';

class PrefsService {
  static const _key = 'subscription_v1';

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
