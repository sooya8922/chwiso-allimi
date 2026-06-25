# 취소표 알리미 — Step 1 폴러

서울 공공 강좌·체육시설(yeyak)에서 **마감된 자리가 다시 열리는 순간**(`예약마감 → 접수중`)을
감지하는 모니터링 프로토타입. 동시에 "취소 시 yeyak이 상태를 되돌리는가?" 가정을 실데이터로 검증한다.

## 실행 (설치 불필요, python3만)

```bash
# 1) 스모크 테스트 (인증키 없이 sample 5건)
python3 poller.py

# 2) 실제 인증키로 전체 폴링 1회
SEOUL_API_KEY=발급키 python3 poller.py

# 3) 접수기간 중 취소표 감지 — 120초 간격 반복
SEOUL_API_KEY=발급키 python3 poller.py --interval 120

# 4) 지금까지 잡힌 전환 리포트
python3 poller.py --report
```

## 인증키 발급 (무료, 즉시)
서울 열린데이터광장 → https://data.seoul.go.kr → 로그인 → 마이페이지 > 인증키 신청.
`ListPublicReservationSport/Education/Culture` 가 같은 키로 동작.

## 데이터
- 결과는 `chwiso.db` (SQLite)에 저장: `service_current`, `status_log`, `transition_log`
- `transition_log.in_window=1` = 접수기간 내 닫힘→접수중 = **진짜 취소표 후보**

## 다음
- Step 2: 전환 감지 → FCM 푸시
- Step 3: Flutter 앱 (탐색/관심등록/내알림)
