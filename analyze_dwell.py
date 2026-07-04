#!/usr/bin/env python3
"""
취소표 4차 검증 판정기 — validation4.log(EVT/수집 라인)를 읽어 dwell을 계산하고
'진짜 취소표(분 단위 organic 전환)'인지 'sleep/배치 아티팩트'인지 자동 분류한다.

지난 실패의 교훈 반영:
  1) 폴 간격이 크게 벌어진 구간(gap) = 노트북 sleep → 그 경계에서 잡힌 전환은 신뢰 불가로 격리.
  2) 같은 '초'에 N건 동시 전환 = yeyak 서버 일괄 재계산(batch) → organic 아님으로 격리.
  3) 남은 '깨끗한' OPEN에 대해서만 dwell(같은 svcid의 OPEN→다음 CLOSE 시간차)을 잰다.

사용법:  python3 analyze_dwell.py [로그경로]   (기본 validation4.log)
"""
import re, sys
from collections import defaultdict, Counter
from datetime import datetime

LOG = sys.argv[1] if len(sys.argv) > 1 else "validation4.log"
TS = "%Y-%m-%d %H:%M:%S"

poll_times = []                      # 모든 '수집' 폴 시각 (해상도/gap 판정용)
evts = []                            # (dt, kind, svcid, label)
evt_re = re.compile(r"^EVT (\d{4}-\d\d-\d\d \d\d:\d\d:\d\d) (OPEN|CLOSE)\s+(\S+)\s+(.*)$")
poll_re = re.compile(r"^\[(\d{4}-\d\d-\d\d \d\d:\d\d:\d\d)\] 수집")

try:
    lines = open(LOG, encoding="utf-8").read().splitlines()
except FileNotFoundError:
    print(f"❌ 로그 없음: {LOG} — 먼저 ./validate4.sh 로 폴러를 돌리세요.")
    sys.exit(1)

for ln in lines:
    m = poll_re.match(ln)
    if m:
        poll_times.append(datetime.strptime(m.group(1), TS)); continue
    m = evt_re.match(ln)
    if m:
        evts.append((datetime.strptime(m.group(1), TS), m.group(2), m.group(3), m.group(4)))

if not poll_times:
    print(f"❌ 폴 기록 0건 — 폴러가 아직 안 돌았거나 로그가 빔.")
    sys.exit(1)

# ── 1) 폴 해상도 / gap(=sleep 의심 구간) 분석 ──────────────────────────────
poll_times.sort()
span_h = (poll_times[-1] - poll_times[0]).total_seconds() / 3600
deltas = [(poll_times[i] - poll_times[i-1]).total_seconds() for i in range(1, len(poll_times))]
GAP_SEC = 300   # 60초 폴에서 5분 넘게 벌어지면 = 멈췄던 것(sleep/네트워크). 그 경계 전환은 의심.
gaps = [(poll_times[i-1], poll_times[i], d) for i, d in enumerate(deltas, 1) if d > GAP_SEC]
clean_ratio = sum(1 for d in deltas if d <= GAP_SEC) / len(deltas) if deltas else 0

# 주간(09~18시) 커버리지 — 취소표가 실제로 나는 시간대를 봤는지
day_polls = [t for t in poll_times if 9 <= t.hour < 18]

def near_gap(dt):
    """이 시각이 gap 경계(재개 직후 등) 부근인가 = sleep 아티팩트 의심."""
    for g0, g1, _ in gaps:
        if abs((dt - g1).total_seconds()) <= 90 or abs((dt - g0).total_seconds()) <= 90:
            return True
    return False

# ── 2) 배치(같은 초 동시 다발) 격리 ────────────────────────────────────────
by_second = Counter(dt for dt, k, _, _ in evts if k == "OPEN")
BATCH_N = 3   # 같은 초에 OPEN 3건 이상 = 서버 일괄 재계산으로 간주
batch_seconds = {s for s, c in by_second.items() if c >= BATCH_N}

# ── 3) dwell 계산: 각 svcid의 OPEN → 그 이후 첫 CLOSE ──────────────────────
seq = defaultdict(list)
for dt, k, sid, label in sorted(evts):
    seq[sid].append((dt, k, label))

clean_dwells = []      # (svcid, open_dt, dwell_min, label)  ← 신뢰 가능한 organic 취소표 후보
flagged = []           # 아티팩트로 격리된 OPEN
open_no_close = []     # 아직 안 닫힌 OPEN (관찰 중)

for sid, ev in seq.items():
    for i, (dt, k, label) in enumerate(ev):
        if k != "OPEN":
            continue
        reason = []
        if dt in batch_seconds: reason.append("batch")
        if near_gap(dt):        reason.append("gap")
        # 이 OPEN 다음의 첫 CLOSE
        close_dt = next((d2 for d2, k2, _ in ev[i+1:] if k2 == "CLOSE"), None)
        if reason:
            flagged.append((dt, sid, "+".join(reason), label)); continue
        if close_dt is None:
            open_no_close.append((dt, sid, label)); continue
        dwell_min = (close_dt - dt).total_seconds() / 60
        clean_dwells.append((sid, dt, dwell_min, label))

# ── 리포트 ────────────────────────────────────────────────────────────────
print("=" * 64)
print("취소표 4차 검증 — dwell 판정 리포트")
print("=" * 64)
print(f"관측 구간 : {poll_times[0]} ~ {poll_times[-1]}  ({span_h:.1f}h)")
print(f"폴 횟수   : {len(poll_times)}회 | 60초 준수율(≤5분): {clean_ratio*100:.0f}%")
print(f"주간(09-18) 폴: {len(day_polls)}회  ← 취소표는 주로 이 시간대 발생")
print(f"큰 gap(>{GAP_SEC//60}분, sleep 의심): {len(gaps)}건", end="")
if gaps:
    print("  →", ", ".join(f"{g0:%m/%d %H:%M}~{g1:%H:%M}({d/60:.0f}분)" for g0,g1,d in gaps[:5]))
else:
    print("  (없음 = 상시가동 성공)")
print(f"배치(같은 초 ≥{BATCH_N}건 OPEN): {len(batch_seconds)}개 초에 몰림 = 서버 일괄 재계산")
print("-" * 64)
print(f"총 OPEN 이벤트         : {sum(1 for _,k,_,_ in evts if k=='OPEN')}")
print(f"  ├ 아티팩트 격리      : {len(flagged)}  (batch/gap 경계)")
print(f"  ├ 아직 안 닫힘(관찰중): {len(open_no_close)}")
print(f"  └ ✅깨끗한 organic    : {len(clean_dwells)}  ← 진짜 취소표 후보")
print("=" * 64)

if clean_dwells:
    clean_dwells.sort(key=lambda x: x[2])
    print("\n🔔 깨끗한 취소표 후보 (dwell = 떴다 다시 닫히기까지):")
    for sid, dt, dw, label in clean_dwells:
        tag = "🔥긴급(≤15분)" if dw <= 15 else ("보통(≤60분)" if dw <= 60 else "느림(>60분)")
        print(f"  {dt:%m/%d %H:%M} dwell={dw:6.1f}분 {tag}  {label[:40]}")
    short = [d for *_, d, _ in [(0,0,x[2],0) for x in clean_dwells] if d <= 15]
    med = sum(x[2] for x in clean_dwells) / len(clean_dwells)
    print("\n--- 판정 ---")
    if any(x[2] <= 15 for x in clean_dwells):
        print("✅ GO: 분~십수분 dwell의 organic 취소표 확인 → '취소표 알림' 킬러기능 성립. Step2 FCM 진행.")
    elif med <= 60:
        print("🟡 애매: dwell이 수십분대. 긴급성 약함 → 취소표보단 '재오픈 알림'이 정직. 판단 필요.")
    else:
        print("↩️ 피벗: dwell이 길다(>1h). 취소표 긴급성 없음 → '재오픈/접수시작 알림'.")
else:
    print("\n>>> 깨끗한 organic 취소표 0건.")
    if len(day_polls) < 60:
        print("    단, 주간 폴이 부족(%d회)해서 '취소표 나는 시간대'를 충분히 못 봄." % len(day_polls))
        print("    → 아직 결론 이르다. 평일 주간에 더 돌릴 것.")
    else:
        print("    주간 커버리지 충분한데도 0건 → 취소표 가설 기각, '재오픈 알림'으로 피벗 확정.")
