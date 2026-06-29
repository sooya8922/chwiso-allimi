#!/usr/bin/env bash
# 고해상도 검증 러너 — 2분 간격으로 yeyak 폴링, 세션과 무관하게 상시 동작.
# 사용: SEOUL_API_KEY를 ~/chwiso-allimi/.seoul_key (chmod 600)에 한 줄로 넣고 실행.
set -euo pipefail
cd "$(dirname "$0")"

KEYFILE="$HOME/chwiso-allimi/.seoul_key"
[ -f "$KEYFILE" ] || { echo "키 파일 없음: $KEYFILE"; exit 1; }
export SEOUL_API_KEY="$(cat "$KEYFILE")"
export CHWISO_DB="$HOME/chwiso-allimi/validation.db"   # 검증 전용 DB (실DB와 분리)
export CATEGORIES="education,culture"

LOG="$HOME/chwiso-allimi/highres.log"
echo "=== highres 폴러 시작 $(date -u +%FT%TZ) / 120초 간격 / DB=$CHWISO_DB ===" >> "$LOG"
# setsid로 완전 분리 — Claude 세션이 끝나도 계속 돈다.
setsid nohup python3 poller.py --interval 120 >> "$LOG" 2>&1 &
echo "started pid=$! (로그: $LOG)"
