#!/usr/bin/env bash
# 취소표 4차(최종) 검증 러너 — 주간 창 + 60초 집중 폴링 + sleep 방지 + 세션 분리
# 결과는 validation4.log(EVT/수집 라인)로 남고, analyze_dwell.py로 판정한다.
set -u
cd "$(dirname "$0")"

export SEOUL_API_KEY="$(cat .seoul_key)"
export CHWISO_DB="$PWD/validation4.db"
export CATEGORIES="education,culture"   # 제품 타깃(선착순 강좌/체험/문화). sport은 list상태 부정확이라 제외
LOG="$PWD/validation4.log"

# 새 검증 = 깨끗한 baseline부터
rm -f "$CHWISO_DB" "$LOG"

# WSL 안 systemd-inhibit는 Windows 호스트 절전을 못 막고 polkit 권한도 거부됨 → 미사용.
# 진짜 sleep 방지는 Windows 전원설정(별도 안내). sleep 공백은 analyze_dwell.py의 gap탐지로 격리.
# setsid+nohup으로 터미널/세션 종료에도 폴러 생존.
setsid nohup python3 -u poller.py --interval 60 >"$LOG" 2>&1 &

PID=$!
echo "validate4 시작: pid=$PID"
echo "  로그:  $LOG"
echo "  DB:    $CHWISO_DB (검증전용, 실DB와 분리)"
echo "  분석:  python3 analyze_dwell.py"
echo "  중단:  pkill -f 'poller.py --interval 60'"
