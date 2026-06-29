# Railway 상시 폴러 배포 가이드 (취소표 가설 검증용)

목적: 회사 노트북/GitHub Actions로는 **상시 가동이 안 돼서** 취소표 dwell(슬롯이 떴다 채워지는 시간)을
못 쟀다. Railway에 **2분 무중단 폴러**를 올려 진짜 dwell을 로그로 측정한다.

## 왜 Railway / 비용
- 며칠짜리 *검증*에는 Railway **$5 무료 체험 크레딧**으로 충분(작은 워커는 하루 ~$0.1~0.3 → 며칠치 = 체험 크레딧 안쪽).
- 만약 검증 후 **24/7 실서비스**로 계속 둘 거면 체험 종료 뒤 Hobby ~$5/월. 평생 $0를 원하면 Oracle Cloud Always-Free VM이 대안(셋업은 더 무거움).

## 배포 절차 (브라우저, 5분)
1. https://railway.app → **Login with GitHub** (sooya8922 계정).
2. **New Project → Deploy from GitHub repo** → `sooya8922/chwiso-allimi` 선택.
   - Railway GitHub App에 이 repo 접근 권한 부여(처음 1회).
3. Railway가 자동 빌드(Nixpacks가 `requirements.txt`/`.python-version` 보고 Python으로 인식, `railway.toml`의 startCommand 사용).
4. 서비스 클릭 → **Variables** 탭 → 변수 추가:
   - `SEOUL_API_KEY` = (data.seoul.go.kr 인증키)  ← **필수**
   - `CATEGORIES` = `education,culture`  (선택, 기본값 동일)
5. **Deploy** 후 **Logs** 탭 확인. 정상이면 2분마다:
   ```
   [2026-06-29 14:00:00] 수집 1600건 | 상태분포: {...}
   EVT 2026-06-29 14:02:00 OPEN  S2606... [성동구] (토)청계천 곤충 탐험대
   EVT 2026-06-29 14:18:00 CLOSE S2606... [성동구] (토)청계천 곤충 탐험대
   ```
   - `OPEN` = 마감→접수중(취소표 후보 떴다), `CLOSE` = 접수중→마감(슬롯 채워짐/기간종료).
   - 같은 svcid의 OPEN→CLOSE 시간차 = **dwell**. 이게 핵심 측정값.

## 며칠 뒤 판정
- **dwell이 분~십수 분(짧음)** = 인기 슬롯이 금방 채워짐 = "취소표 떴어요 빨리!" 긴급성 성립 → **GO**, Step2 FCM 푸시로.
- **dwell이 몇 시간(긺)** = 긴급성 약함 → "재오픈/접수시작 알림"으로 피벗.
- OPEN이 하루 몇 번 안 뜨고 24시간 흩어져 있으면(노트북 sleep 아티팩트 없는 깨끗한 데이터) 그 빈도 자체가 시장 크기 신호.

## 로그 보는 법 (CLI, 선택)
```
npm i -g @railway/cli && railway login
railway link    # 프로젝트 선택
railway logs | grep "^EVT"
```
