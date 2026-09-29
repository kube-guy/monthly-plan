# monthly-plan

한 달의 일정과 장소를 한눈에 보는 Swift macOS 앱입니다. 문장으로 일정을 추가하고, 달력과 **이달의 순간들**을 PNG/JPG로 저장할 수 있습니다. Supabase에 연결하면 여러 Mac에서 같은 계정의 일정을 동기화합니다.

빈 달력으로 시작하며, 입력한 일정만 표시됩니다.

## 설치

macOS 14 이상, Swift 6 도구 체인(Xcode 또는 Command Line Tools)이 필요합니다.

```sh
brew install kube-guy/kit/monthly-plan
monthly-plan
```

Homebrew가 처음 사용하는 외부 formula의 신뢰 확인을 요구하면 내용을 검토한 뒤 `brew trust --formula kube-guy/kit/monthly-plan`을 실행하세요. 소스에서 Mac에 맞춰 빌드하며, 별도 서버를 실행할 필요가 없습니다.

직접 빌드:

```sh
swift build --disable-sandbox -c release --product monthly-plan
bash scripts/package-app.sh --skip-build
open 'build/Monthly Plan.app'
```

이 앱은 로컬에서 ad hoc 서명되며 Apple 공증을 받은 배포 바이너리는 아닙니다. 저장 위치와 Supabase 설정은 앱 업데이트 후에도 유지됩니다.

## 할 수 있는 일

- 월별 달력, 날짜 필터, 일정 추가·수정·삭제, 분류별 색상
- 장소 검색과 Apple 지도 표시, 상세에서 **네이버지도 장소 검색** 열기
- 한국어 문장을 날짜·시간·장소·제목으로 분석하고 수정 가능한 미리보기 제공
- 달력 / 이달의 순간들 / 둘 다 선택하여 PNG 또는 JPG로 내보내기
- 로그인된 Codex CLI의 웹 검색으로 주차 정보와 방문 후기 요약, 출처 링크 표시
- Supabase 로그인, 여러 Mac 동기화, 오프라인 변경 보관, 충돌 시 두 내용 비교

현재 앱 안의 지도는 **Apple 지도**입니다. 네이버지도는 상세 화면에서 외부 링크로 연결됩니다. 지도와 외부 리뷰는 이미지 내보내기에 포함되지 않습니다.

## 문장으로 일정 추가

```text
내일 오후 3시 서울숲에서 산책
10월 3일 오후 2시부터 4시까지 성수동 카페에서 친구 만나기
다음주 화요일 오전 10시 사무실에서 회의
10월 9일 오후 2시 장소: 국립현대미술관 서울, 제목: 전시 보기
```

한 줄에 한 일정, 최대 20개를 추가할 수 있습니다. 분석은 이 Mac에서 수행하며 외부 AI에 문장을 보내지 않습니다. 날짜와 시간은 한국 시간 기준입니다. `3시`처럼 오전·오후가 불명확한 표현은 직접 확인하도록 표시합니다. 문장의 장소는 텍스트로 등록되며, 일정 수정에서 검색 결과를 선택하면 지도에 표시됩니다. 하루를 넘기는 일정과 반복 일정은 현재 지원하지 않습니다.

## 여러 Mac에서 같은 일정 보기

앱 상단 **클라우드 연결**에서 Supabase 프로젝트 URL과 publishable/anon 키를 입력한 뒤 이메일의 로그인 링크를 같은 Mac에서 열어 로그인하세요. 다른 Mac에도 같은 프로젝트를 연결하고 같은 이메일로 로그인하면 됩니다.

**먼저 [Supabase 설정 안내](docs/SUPABASE.md)에 따라 데이터베이스와 인증 메일을 설정해야 합니다.** Supabase 관리 화면에 GitHub 계정으로 로그인하는 것과 앱 안에서 일정을 동기화하는 사용자 로그인은 별개입니다.

- 저장 직후, 앱 활성화 시, 앱이 열린 동안 약 60초마다 동기화합니다.
- 오프라인 변경은 SQLite에 보관하고 다음 연결에서 재시도합니다. 앱 종료 중에는 동기화하지 않습니다.
- 동시에 수정하면 조용히 덮어쓰지 않고 **계정 · 동기화** 화면에서 선택하도록 합니다.
- 삭제 기록도 동기화해 오프라인 Mac에서 일정이 다시 나타나는 것을 방지합니다.
- 계정별 캐시를 분리합니다. 로그아웃해도 해당 계정의 캐시와 미전송 변경은 보관됩니다.
- 로그인 전 작성한 일정은 자동 전송하지 않습니다. **이 Mac의 기존 일정 가져오기**에서 현재 계정으로 복사할 수 있습니다. 다시 가져오면 중복될 수 있습니다.
- 본인 계정의 여러 Mac을 위한 동기화입니다. 타 사용자와의 공동 캘린더는 아직 지원하지 않습니다.

## 주차와 리뷰 자동 조회

먼저 [Codex CLI](https://learn.chatgpt.com/docs/codex/cli)를 설치하고 `codex login`으로 ChatGPT 계정에 로그인합니다. 일정 상세를 열면 앱이 Codex CLI의 웹 검색을 실행해 주차 정보와 후기의 공통된 경향을 요약하고, 확인한 출처를 링크로 보여줍니다. 별도 OpenAI API 키는 필요하지 않습니다. 장소명과 주소만 전달하며 일정 제목과 메모는 보내지 않습니다.

터미널에서도 `monthly-plan --summarize-place "서울숲" "서울 성동구 뚝섬로 273"`으로 같은 조회 결과를 JSON으로 확인할 수 있습니다.

Codex 계정의 사용량 한도가 적용됩니다. 다른 Mac에서도 Codex CLI 설치와 로그인이 필요합니다. 출처를 확인할 수 없으면 요약을 표시하지 않습니다. AI 요약에는 오류나 오래된 정보가 있을 수 있으므로 주차 가능 여부와 요금은 방문 전 원문 또는 장소에 확인하세요. 앱은 네이버 리뷰를 직접 수집하거나 크롤링하지 않습니다.

요약은 앱 실행 중 메모리에서 30분간 재사용하며 디스크나 Supabase에 저장하지 않습니다. Codex 실행에는 읽기 전용 권한과 임시 세션을 사용합니다. 이전 버전에서 저장한 Google 장소 ID는 기존 동기화 데이터와의 호환성을 위해 남지만 새 조회에는 사용하지 않습니다.

## 데이터 보관

- 온라인: 연결한 Supabase 프로젝트의 PostgreSQL, 로그인 사용자별 접근 제한(RLS)
- 로컬: `~/Library/Application Support/monthly-plan/`
- 계정별 로컬 캐시: 위 폴더의 `accounts/<project hash>/<user ID>/`
- Supabase 인증 토큰: macOS 키체인
- 프로젝트 URL·공개 API 키: macOS 앱 설정

로컬 백업은 앱을 종료한 뒤 위 폴더 **전체**를 복사하세요. SQLite 파일 하나를 iCloud Drive에서 동시에 공유하는 방식은 사용하지 않습니다. 클라우드 동기화는 백업과 다르므로 Supabase의 별도 백업 정책도 설정하세요.

## 검증과 개발

```sh
swift run --disable-sandbox MonthlyPlanChecks
swift build --disable-sandbox -c release --product monthly-plan
.build/release/monthly-plan --version
.build/release/monthly-plan --export-empty /tmp/monthly-plan.png
.build/release/monthly-plan --export-empty /tmp/monthly-plan.jpg
```

Foundation 기반 검사 실행기를 포함하므로 XCTest가 없는 Command Line Tools 환경에서도 검증할 수 있습니다. 실제 Supabase 연결에는 위 설정과 이메일 인증이 필요합니다. [`supabase/tests`](supabase/tests)의 SQL 검사는 별도의 테스트 데이터베이스에서만 실행하세요.

[개인정보 처리 안내](PRIVACY.md) · [이용 안내](TERMS.md) · [MIT License](LICENSE)
