# Google Calendar 직접 연결

이 직접 연결은 Google Calendar 일정을 **읽기 전용**으로 월별 달력에 표시합니다. 앱의 Supabase 로그인 계정과는 별개이며 일정 본문을 Supabase에 저장하지 않습니다. Mac **시스템 설정 → 인터넷 계정**에 Google 계정을 연결한 뒤 앱의 **Mac 캘린더 읽기 허용** 기능을 사용할 수도 있습니다. 이 Mac 캘린더 방식에서는 Supabase 로그인 후 **선택한 Mac 캘린더 일정을 Supabase에 동기화**를 켜면 일정의 제목·시간·장소·메모가 계정에 저장되어 다른 Mac에도 표시됩니다. **동기화할 일정 → 개별로 선택한 일정만**을 고르면 현재 달의 일정마다 전송 여부를 정할 수 있습니다. 선택 해제는 이후 전송만 멈추며 기존 Supabase 복사본은 지우지 않습니다.

1. [Google Cloud Console](https://console.cloud.google.com/apis/credentials)에서 이 앱에 사용할 프로젝트를 선택하거나 만듭니다. 프로젝트에서 **Google Calendar API**를 사용 설정합니다.
2. Google Auth Platform에서 동의 화면의 앱 이름, 지원 이메일과 대상 사용자를 설정합니다. 필요한 권한 범위는 계정 주소 표시를 위한 `openid email`과 캘린더 읽기용 `https://www.googleapis.com/auth/calendar.calendarlist.readonly`, `https://www.googleapis.com/auth/calendar.events.readonly`입니다. Gmail 내용 읽기 권한은 요청하지 않습니다. 테스트 상태라면 접속할 Google 계정을 테스트 사용자에 추가합니다.
3. OAuth 클라이언트 ID를 **데스크톱 앱** 유형으로 만듭니다. 표시되는 **Client ID**만 복사합니다. Client Secret은 앱에 입력하거나 공개 저장소에 넣지 않습니다.
4. monthly-plan의 **계정 · 동기화 → Gmail 계정 추가**에 Client ID를 붙여 넣고 추가 버튼을 누릅니다. 기본 브라우저에서 로그인과 읽기 권한을 허용하면 앱으로 돌아옵니다. 기본 캘린더가 자동 선택되며, 다른 캘린더도 체크할 수 있습니다. 같은 방법으로 다른 Gmail 계정을 더 추가할 수 있습니다. Client ID는 다음 계정을 추가할 때 이 Mac에서 다시 입력하지 않아도 됩니다.

다른 Mac에서도 각 Mac의 앱에서 같은 Gmail로 한 번 로그인해야 합니다. Google 인증 토큰을 Supabase로 전송하거나 Mac 사이에 공유하지 않습니다. 접근·갱신 토큰과 계정 주소는 연결한 Mac의 키체인에 저장되며, 계정별 연결 해제 시 삭제됩니다. Google Cloud의 외부 앱이 **Testing** 상태면 일부 권한의 갱신 토큰은 7일 뒤 만료될 수 있어 재연결이 필요합니다. 일반 사용자에게 공개하려면 Google의 민감한 범위 검증이 필요할 수 있습니다. 같은 캘린더를 Mac 캘린더 방식과 직접 연결 방식에서 모두 선택하면 중복 표시됩니다.

참고: [데스크톱 앱 OAuth](https://developers.google.com/identity/protocols/oauth2/native-app), [Calendar API 권한 범위](https://developers.google.com/workspace/calendar/api/auth), [OAuth 게시 상태](https://developers.google.com/identity/protocols/oauth2)
