#!/usr/bin/env python3
"""
취소표 알리미 — Step 1 폴러 (가정 검증용)

서울 공공서비스예약(yeyak) API 3종을 주기적으로 긁어서
서비스별 접수상태(SVCSTATNM)를 SQLite에 기록하고,
'예약마감/접수마감 → 접수중' 상태 전환(=취소표 후보)을 잡아 로그로 남긴다.

핵심 목적:
  1) 앱의 심장(상태 모니터링) 프로토타입
  2) "취소가 발생하면 yeyak이 정말 상태를 접수중으로 되돌리는가?" 가정을
     실데이터로 자동 검증 (transition_log 테이블에 쌓임)

의존성: 파이썬 표준 라이브러리만 (설치 불필요). 어디서든 실행 가능.

사용법:
  # 1회 실행 (스모크 테스트, 인증키 없으면 sample키로 5건만)
  python3 poller.py

  # 실제 인증키로 1회
  SEOUL_API_KEY=발급받은키 python3 poller.py

  # N초마다 반복 (접수기간 중 취소표 감지하려면 60~300초 권장)
  SEOUL_API_KEY=발급받은키 python3 poller.py --interval 120

  # 지금까지 잡힌 취소표 후보 전환 보기
  python3 poller.py --report
"""

import argparse
import json
import os
import sqlite3
import sys
import time
import urllib.request
from datetime import datetime

# ── 설정 ────────────────────────────────────────────────────────────────
API_KEY = os.environ.get("SEOUL_API_KEY", "sample")  # sample = 5건 제한(테스트용)
DB_PATH = os.environ.get("CHWISO_DB", os.path.join(os.path.dirname(os.path.abspath(__file__)), "chwiso.db"))
PAGE = 1000  # 서울 API 1회 최대 1000행 (sample키는 5행만 반환)

# 폴링할 예약 카테고리 (기본: 선착순 모집형 = 강좌/체험/문화)
# 시설형(테니스/풋살 등)까지 보려면 CATEGORIES=sport,education,culture
ALL_SERVICES = {"sport": "ListPublicReservationSport",
                "education": "ListPublicReservationEducation",
                "culture": "ListPublicReservationCulture"}
_cats = [c.strip() for c in os.environ.get("CATEGORIES", "education,culture").split(",")]
SERVICES = [ALL_SERVICES[c] for c in _cats if c in ALL_SERVICES] or list(ALL_SERVICES.values())

# '열려있음'으로 볼 상태
OPEN_STATES = {"접수중"}
# '닫혀있음'으로 볼 상태 (여기서 접수중으로 바뀌면 = 취소표 후보)
CLOSED_STATES = {"예약마감", "접수마감"}

BASE = "http://openapi.seoul.go.kr:8088"


# ── DB ──────────────────────────────────────────────────────────────────
def db():
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    conn.execute("""CREATE TABLE IF NOT EXISTS service_current(
        svcid TEXT PRIMARY KEY, category TEXT, svcnm TEXT, area TEXT,
        minclass TEXT, status TEXT, rcptbgn TEXT, rcptend TEXT,
        x TEXT, y TEXT, svcurl TEXT, updated_at TEXT)""")
    conn.execute("""CREATE TABLE IF NOT EXISTS status_log(
        id INTEGER PRIMARY KEY AUTOINCREMENT, svcid TEXT, status TEXT, observed_at TEXT)""")
    conn.execute("""CREATE TABLE IF NOT EXISTS transition_log(
        id INTEGER PRIMARY KEY AUTOINCREMENT, svcid TEXT, svcnm TEXT, area TEXT,
        from_status TEXT, to_status TEXT, in_window INTEGER, observed_at TEXT, svcurl TEXT)""")
    conn.commit()
    return conn


# ── API ─────────────────────────────────────────────────────────────────
def fetch(service):
    """서비스 한 종을 페이지네이션하며 전부 가져온다."""
    rows, start = [], 1
    page = 5 if API_KEY == "sample" else PAGE  # sample키는 5건 제한
    while True:
        end = start + page - 1
        url = f"{BASE}/{API_KEY}/json/{service}/{start}/{end}/"
        try:
            with urllib.request.urlopen(url, timeout=30) as r:
                data = json.loads(r.read().decode("utf-8"))
        except Exception as e:
            print(f"  ! {service} 요청 실패: {e}", file=sys.stderr)
            break
        key = next((k for k in data if k != "RESULT"), None)
        if not key or "row" not in data.get(key, {}):
            # RESULT 코드 확인 (INFO-000 성공)
            res = data.get("RESULT") or (data.get(key, {}) or {}).get("RESULT", {})
            if res and res.get("CODE") not in ("INFO-000", None):
                print(f"  ! {service}: {res.get('CODE')} {res.get('MESSAGE')}", file=sys.stderr)
            break
        block = data[key]
        rows.extend(block["row"])
        total = block.get("list_total_count", len(rows))
        if API_KEY == "sample" or len(rows) >= total or len(block["row"]) < page:
            break
        start += page
    return rows


def in_window(rcptbgn, rcptend, now):
    """현재가 접수기간 안인가."""
    try:
        fmt = "%Y-%m-%d %H:%M:%S.%f"
        b = datetime.strptime(rcptbgn, fmt) if rcptbgn else None
        e = datetime.strptime(rcptend, fmt) if rcptend else None
        if b and now < b:
            return False
        if e and now > e:
            return False
        return True
    except Exception:
        return False


# ── 1회 폴링 ─────────────────────────────────────────────────────────────
def poll_once(conn):
    now = datetime.now()
    now_s = now.strftime("%Y-%m-%d %H:%M:%S")
    transitions, counts = [], {}
    seen = 0
    for service in SERVICES:
        rows = fetch(service)
        seen += len(rows)
        for r in rows:
            svcid = r.get("SVCID")
            if not svcid:
                continue
            status = r.get("SVCSTATNM", "")
            counts[status] = counts.get(status, 0) + 1
            prev = conn.execute("SELECT status FROM service_current WHERE svcid=?", (svcid,)).fetchone()
            prev_status = prev["status"] if prev else None

            # 상태가 바뀌었으면 로그
            if prev_status != status:
                conn.execute("INSERT INTO status_log(svcid,status,observed_at) VALUES(?,?,?)",
                             (svcid, status, now_s))
                # 닫힘 → 접수중 = 취소표 후보
                if prev_status in CLOSED_STATES and status in OPEN_STATES:
                    win = 1 if in_window(r.get("RCPTBGNDT"), r.get("RCPTENDDT"), now) else 0
                    conn.execute("""INSERT INTO transition_log
                        (svcid,svcnm,area,from_status,to_status,in_window,observed_at,svcurl)
                        VALUES(?,?,?,?,?,?,?,?)""",
                        (svcid, r.get("SVCNM"), r.get("AREANM"), prev_status, status, win, now_s, r.get("SVCURL")))
                    transitions.append((r.get("AREANM"), r.get("SVCNM"), prev_status, status, win))

            conn.execute("""INSERT INTO service_current
                (svcid,category,svcnm,area,minclass,status,rcptbgn,rcptend,x,y,svcurl,updated_at)
                VALUES(?,?,?,?,?,?,?,?,?,?,?,?)
                ON CONFLICT(svcid) DO UPDATE SET status=excluded.status,
                    rcptbgn=excluded.rcptbgn, rcptend=excluded.rcptend, updated_at=excluded.updated_at""",
                (svcid, service, r.get("SVCNM"), r.get("AREANM"), r.get("MINCLASSNM"), status,
                 r.get("RCPTBGNDT"), r.get("RCPTENDDT"), r.get("X"), r.get("Y"), r.get("SVCURL"), now_s))
    conn.commit()
    print(f"[{now_s}] 수집 {seen}건 | 상태분포: {counts}")
    if transitions:
        print(f"  🔔 취소표 후보 {len(transitions)}건!")
        for area, nm, f, t, win in transitions:
            mark = "✅접수기간내" if win else "⚠️기간밖"
            print(f"     [{area}] {nm}: {f}→{t} {mark}")
    return len(transitions)


# ── 리포트 ───────────────────────────────────────────────────────────────
def export_transitions(conn, path):
    """transition_log 전체를 깃 친화적 JSONL 텍스트로 덤프 (CI 커밋용)."""
    with open(path, "w", encoding="utf-8") as f:
        for row in conn.execute("""SELECT observed_at,area,svcnm,from_status,to_status,in_window,svcurl
                                   FROM transition_log ORDER BY id"""):
            f.write(json.dumps(dict(row), ensure_ascii=False) + "\n")


def report(conn):
    n = conn.execute("SELECT COUNT(*) c FROM transition_log").fetchone()["c"]
    nw = conn.execute("SELECT COUNT(*) c FROM transition_log WHERE in_window=1").fetchone()["c"]
    sc = conn.execute("SELECT COUNT(*) c FROM service_current").fetchone()["c"]
    print(f"=== 취소표 가정 검증 리포트 ===")
    print(f"추적 중 서비스: {sc}건")
    print(f"닫힘→접수중 전환 총 {n}건 (그중 접수기간 내 {nw}건 = 진짜 취소표 후보)")
    if nw > 0:
        print("\n>>> 가정 성립 신호: yeyak이 취소 시 상태를 되돌린다. 앱 컨셉 GO ✅")
    elif n > 0:
        print("\n>>> 전환은 있으나 접수기간 밖. 재오픈/재공고일 수 있음 — 더 관찰 필요.")
    else:
        print("\n>>> 아직 전환 없음. 인기 강좌 접수기간에 60~120초 간격으로 더 돌려볼 것.")
    print("\n최근 전환 10건:")
    for row in conn.execute("""SELECT observed_at,area,svcnm,from_status,to_status,in_window
                               FROM transition_log ORDER BY id DESC LIMIT 10"""):
        mark = "✅" if row["in_window"] else "⚠️"
        print(f"  {row['observed_at']} {mark} [{row['area']}] {row['svcnm']}: {row['from_status']}→{row['to_status']}")


# ── main ────────────────────────────────────────────────────────────────
def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--interval", type=int, default=0, help="N초마다 반복 (0=1회만)")
    ap.add_argument("--report", action="store_true", help="취소표 전환 리포트만 출력")
    args = ap.parse_args()

    conn = db()
    if API_KEY == "sample":
        print("⚠️  SEOUL_API_KEY 미설정 → sample키(5건 제한)로 동작. 실검증은 인증키 발급 후.")

    if args.report:
        report(conn)
        return
    if args.interval > 0:
        print(f"폴링 시작: {args.interval}초 간격 (Ctrl+C 중단)")
        try:
            while True:
                poll_once(conn)
                time.sleep(args.interval)
        except KeyboardInterrupt:
            print("\n중단됨.")
    else:
        poll_once(conn)

    # CI/깃 커밋용 텍스트 결과 항상 갱신
    export_transitions(conn, os.path.join(os.path.dirname(DB_PATH), "transitions.jsonl"))


if __name__ == "__main__":
    main()
