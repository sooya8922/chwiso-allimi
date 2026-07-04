#!/usr/bin/env python3
"""
feed.json 생성기 — chwiso.db(poller가 유지)를 읽어 앱이 소비할 정적 피드를 만든다.

구조:
{
  "version": 1,
  "generated_at": "YYYY-MM-DD HH:MM:SS",   # KST
  "counts": {...},
  "courses":  [...],   # 접수중/안내중/예약마감 강좌 (접수종료·일시중지 제외)
  "new":      [...],   # 최근 48h 내 처음 등장한 svcid (신규 강좌 알림용)
  "reopened": [...],   # 최근 7일 내 닫힘→접수중 전환 (재오픈 알림용)
  "upcoming": [...]    # 접수시작이 미래인 강좌 (광클 알람 예약용, 리드타임 포함)
}

설계 노트:
- 서울 데이터 일시는 전부 KST. GH Actions(UTC) 러너에서도 틀어지지 않게 KST 고정.
- 강좌명에 HTML 엔티티(&lt; &#39; &middot;)가 섞여 옴 → html.unescape로 정규화.
- 앱은 raw.githubusercontent.com 으로 이 파일만 받는다(서버 불필요).
"""
import html
import json
import os
import sqlite3
import sys
from datetime import datetime, timezone, timedelta

KST = timezone(timedelta(hours=9))
DB_PATH = os.environ.get("CHWISO_DB", os.path.join(os.path.dirname(os.path.abspath(__file__)), "chwiso.db"))
OUT_PATH = os.environ.get("FEED_OUT", os.path.join(os.path.dirname(os.path.abspath(__file__)), "feed.json"))

NEW_WINDOW_H = 48       # 이 시간 안에 처음 본 강좌 = '신규'
REOPEN_WINDOW_D = 7     # 이 기간의 재오픈 이벤트만 노출
FEED_STATUSES = ("접수중", "안내중", "예약마감")  # 접수종료/예약일시중지 제외


def clean(s):
    """HTML 엔티티 해제 + 공백 정리. None-safe."""
    return html.unescape(str(s)).strip() if s else ""


def parse_dt(s):
    """yeyak 일시 문자열 파싱. 형식 불량이면 None (엣지: 빈값/이상값 방어)."""
    if not s:
        return None
    for fmt in ("%Y-%m-%d %H:%M:%S.%f", "%Y-%m-%d %H:%M:%S"):
        try:
            return datetime.strptime(s, fmt)
        except ValueError:
            continue
    return None


def main():
    now = datetime.now(KST).replace(tzinfo=None)
    now_s = now.strftime("%Y-%m-%d %H:%M:%S")
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row

    courses, upcoming, new = [], [], []
    q = f"""SELECT svcid,category,svcnm,area,minclass,status,rcptbgn,rcptend,x,y,svcurl,
                   payat,usetgt,imgurl,first_seen
            FROM service_current WHERE status IN ({",".join("?"*len(FEED_STATUSES))})
            ORDER BY svcid"""
    for r in conn.execute(q, FEED_STATUSES):
        bgn = parse_dt(r["rcptbgn"])
        c = {
            "id": r["svcid"],
            "name": clean(r["svcnm"]),
            "area": clean(r["area"]),                  # 엣지: 빈 문자열 가능(1.4%) — 앱은 '서울 전역'으로 표기
            "cat": clean(r["minclass"]),
            "status": r["status"],
            "pay": clean(r["payat"]),                  # 무료/유료/유료(요금안내문의) — 레거시 행은 빈값
            "target": clean(r["usetgt"]),
            "rcpt_bgn": (r["rcptbgn"] or "")[:16],
            "rcpt_end": (r["rcptend"] or "")[:16],
            "x": r["x"] or "", "y": r["y"] or "",
            "url": r["svcurl"] or "",
            "img": r["imgurl"] or "",
        }
        courses.append(c)
        if bgn and bgn > now:
            upcoming.append({"id": c["id"], "name": c["name"], "area": c["area"],
                             "open_at": c["rcpt_bgn"],
                             "lead_min": round((bgn - now).total_seconds() / 60)})
        fs = parse_dt(r["first_seen"])
        if fs and (now - fs) <= timedelta(hours=NEW_WINDOW_H):
            new.append({"id": c["id"], "name": c["name"], "area": c["area"],
                        "status": c["status"], "seen_at": r["first_seen"][:16]})

    reopened = []
    cutoff = (now - timedelta(days=REOPEN_WINDOW_D)).strftime("%Y-%m-%d %H:%M:%S")
    for r in conn.execute("""SELECT svcid,svcnm,area,in_window,observed_at,svcurl FROM transition_log
                             WHERE observed_at >= ? ORDER BY id DESC""", (cutoff,)):
        reopened.append({"id": r["svcid"], "name": clean(r["svcnm"]), "area": clean(r["area"]),
                         "in_window": r["in_window"], "at": r["observed_at"][:16]})

    feed = {
        "version": 1,
        "generated_at": now_s,
        "counts": {"courses": len(courses), "new": len(new),
                   "reopened": len(reopened), "upcoming": len(upcoming)},
        "courses": courses,
        "new": new,
        "reopened": reopened,
        "upcoming": sorted(upcoming, key=lambda u: u["open_at"]),
    }
    with open(OUT_PATH, "w", encoding="utf-8") as f:
        json.dump(feed, f, ensure_ascii=False, separators=(",", ":"))
    print(f"feed.json 생성: {feed['counts']} → {OUT_PATH} ({os.path.getsize(OUT_PATH)//1024}KB)")


if __name__ == "__main__":
    main()
