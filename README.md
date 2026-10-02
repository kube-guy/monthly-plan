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
- 달력 / 이달의 순간들 / 둘 다 선택하여 PNG 또는 JPG로 내보내기 (기본 위치: 다운로드 폴더)
- 로그인된 Codex CLI의 웹 검색으로 주차 정보와 방문 후기 요약, 출처 링크 표시
- Supabase 이메일·Google 계정 로그인, 여러 Mac 동기화, 오프라인 변경 보관, 충돌 시 두 내용 비교
- Mac 캘린더 또는 Google 계정 직접 연결로 Google Calendar 일정 읽기 전용 표시

현재 앱 안의 지도는 **Apple 지도**입니다. 네이버지도는 상세 화면에서 외부 링크로 연결됩니다. 지도와 외부 리뷰는 이미지 내보내기에 포함되지 않습니다.

## 문장으로 일정 추가

```text
내일 오후 3시 서울숲에서 산책
10월 3일 오후 2시부터 4시까지 성수동 카페에서 친구 만나기
다음주 화요일 오전 10시 사무실에서 회의
10월 9일 오후 2시 장소: 국립현대미술관 서울, 제목: 전시 보기
```

한 줄에 한 일정, 최대 20개를 추가할 수 있습니다. 분석은 이 Mac에서 수행하며 외부 AI에 문장을 보내지 않습니다. 날짜와 시간은 한국 시간 기준이고, 시간을 생략하면 오전 9시로 설정됩니다. `3시`처럼 오전·오후가 불명확한 표현은 직접 확인하도록 표시합니다. 문장의 장소는 텍스트로 등록되며, 일정 수정에서 검색 결과를 선택하면 지도에 표시됩니다. 하루를 넘기는 일정과 반복 일정은 현재 지원하지 않습니다.

## 여러 Mac에서 같은 일정 보기

앱 상단 **클라우드 연결**에서 Supabase 프로젝트 URL과 publishable/anon 키를 입력한 뒤 이메일 로그인 링크 또는 Google 계정으로 로그인하세요. 다른 Mac에도 같은 프로젝트를 연결하고 같은 계정으로 로그인하면 됩니다.

**먼저 [Supabase 설정 안내](docs/SUPABASE.md)에 따라 데이터베이스와 인증 메일을 설정해야 합니다.** Supabase 관리 화면에 GitHub 계정으로 로그인하는 것과 앱 안에서 일정을 동기화하는 사용자 로그인은 별개입니다.

**계정 · 동기화** 화면의 `연결된 Supabase 프로젝트 열기` 링크로 설정한 프로젝트의 관리 화면을 바로 열 수 있습니다.

이메일 대신 **Google 계정으로 로그인**할 수도 있습니다. 프로젝트 관리자가 [Google 로그인 설정](docs/GOOGLE_LOGIN.md)을 마친 뒤 **계정 · 동기화 → Google 계정으로 로그인**을 누르세요. 같은 이메일이어도 Google 계정으로 처음 로그인하는 경우 Supabase의 계정 연결 상태를 확인하세요. 다른 이메일로 로그인하면 다른 일정 계정이 열립니다.

- 저장 직후, 앱 활성화 시, 앱이 열린 동안 약 60초마다 동기화합니다.
- 오프라인 변경은 SQLite에 보관하고 다음 연결에서 재시도합니다. 앱 종료 중에는 동기화하지 않습니다.
- 동시에 수정하면 조용히 덮어쓰지 않고 **계정 · 동기화** 화면에서 선택하도록 합니다.
- 삭제 기록도 동기화해 오프라인 Mac에서 일정이 다시 나타나는 것을 방지합니다.
- 계정별 캐시를 분리합니다. 로그아웃해도 해당 계정의 캐시와 미전송 변경은 보관됩니다.
- 로그인 전 작성한 일정은 자동 전송하지 않습니다. **이 Mac의 기존 일정 가져오기**에서 현재 계정으로 복사할 수 있습니다. 다시 가져오면 중복될 수 있습니다.
- 본인 계정의 여러 Mac을 위한 동기화입니다. 타 사용자와의 공동 캘린더는 아직 지원하지 않습니다.

## Google Calendar 연결

두 가지 방법이 있습니다. [Google Calendar 직접 연결 설정](docs/GOOGLE_CALENDAR.md)을 마치면 앱의 **계정 · 동기화 → Gmail 계정 추가**에서 여러 계정으로 로그인할 수 있습니다. Mac의 인터넷 계정·캘린더 설정에 의존하지 않습니다. 다른 Mac에서는 같은 Gmail 계정으로 각각 한 번 로그인해야 합니다. 기존 방식인 Mac의 **시스템 설정 → 인터넷 계정**에서 Google 계정을 추가하고 캘린더 동기화를 켠 뒤 앱에서 **Mac 캘린더 읽기 허용**을 누르는 방법도 사용할 수 있습니다. 두 방법 모두 표시할 캘린더를 선택하세요. 일정은 월별 달력과 **이달의 순간들**, PNG/JPG 내보내기에 나타납니다. 여러 날에 걸친 일정은 해당 날짜마다 표시되며 종일 일정은 `종일`로 표시됩니다.

Google 일정은 앱에서 읽기 전용이며 수정·삭제는 원본 캘린더에서 합니다. **Mac 캘린더에서 불러오기**를 사용하고 Supabase에 로그인한 경우, **선택한 Mac 캘린더 일정을 Supabase에 동기화**를 켜면 일정의 제목·시간·장소·메모가 계정에 저장되어 다른 Mac에도 표시됩니다. **동기화할 일정 → 개별로 선택한 일정만**을 고르면 현재 보고 있는 달의 일정을 하나씩 체크할 수 있습니다. 여러 날에 걸친 일정은 한 번의 선택으로 함께 동기화됩니다. Mac 캘린더의 위치 필드가 비어 있으면 `서울숲에서 산책`, `장소: 서울숲`, `산책 @서울숲`처럼 명확한 제목에서 장소를 추출합니다. 캘린더 선택과 업로드 대상은 계정·Mac별로 유지하며, 선택을 해제하거나 동기화를 꺼도 이미 저장된 복사본은 남습니다. **Gmail 계정 추가**로 직접 연결한 Google 일정은 화면에만 표시되고 Supabase에는 전송하지 않습니다. 두 방법으로 같은 캘린더를 모두 선택하면 중복 표시될 수 있습니다.

## 주차와 리뷰 자동 조회

먼저 [Codex CLI](https://learn.chatgpt.com/docs/codex/cli)를 설치하고 `codex login`으로 ChatGPT 계정에 로그인합니다. 일정 상세를 열면 앱이 Codex CLI의 웹 검색을 실행해 주차 정보와 후기의 공통된 경향을 요약하고, 확인한 출처를 링크로 보여줍니다. 별도 OpenAI API 키는 필요하지 않습니다. 장소명과 주소만 전달하며 일정 제목과 메모는 보내지 않습니다.

터미널에서는 `monthly-plan --summarize-place "서울숲" "서울 성동구 뚝섬로 273"`으로 명시적인 일회성 조회 결과를 JSON으로 확인할 수 있습니다.

Codex 계정의 사용량 한도가 적용됩니다. 처음 조회할 Mac에는 Codex CLI 설치와 로그인이 필요합니다. 저장된 요약은 다른 Mac에서 Codex CLI 없이도 표시됩니다. 출처를 확인할 수 없으면 요약을 표시하지 않습니다. AI 요약에는 오류나 오래된 정보가 있을 수 있으므로 주차 가능 여부와 요금은 방문 전 원문 또는 장소에 확인하세요. 앱은 네이버 리뷰를 직접 수집하거나 크롤링하지 않습니다.

앱의 첫 조회 결과는 장소명·주소 조합별로 SQLite에 저장합니다. Supabase에 로그인한 경우 같은 계정으로 동기화되어 다른 Mac에서도 재호출 없이 표시됩니다. 저장된 요약은 자동 갱신하거나 재요청하지 않습니다. 장소명이나 주소를 바꾸면 다른 장소로 취급합니다. Codex 실행에는 읽기 전용 권한과 임시 세션을 사용합니다. 이전 버전에서 저장한 Google 장소 ID는 기존 동기화 데이터와의 호환성을 위해 남지만 새 조회에는 사용하지 않습니다.

## 데이터 보관

- 온라인: 연결한 Supabase 프로젝트의 PostgreSQL, 로그인 사용자별 접근 제한(RLS)
- 로컬: `~/Library/Application Support/monthly-plan/`
- 계정별 로컬 캐시: 위 폴더의 `accounts/<project hash>/<user ID>/`
- Supabase 인증 토큰: macOS 키체인
- 직접 연결한 Google Calendar 인증 토큰: 이 Mac의 키체인
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

Foundation 기반 검사 실행기를 포함하므로 XCTest가 없는 Command Line Tools 환경에서도 검증할 수 있습니다. 실제 Supabase 연결에는 위 설정과 선택한 로그인 방법의 인증이 필요합니다. [`supabase/tests`](supabase/tests)의 SQL 검사는 별도의 테스트 데이터베이스에서만 실행하세요.

[개인정보 처리 안내](PRIVACY.md) · [이용 안내](TERMS.md) · [MIT License](LICENSE)
