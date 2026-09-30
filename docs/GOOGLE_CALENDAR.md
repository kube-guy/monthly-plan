# Google Calendar 직접 연결

이 연결은 Google Calendar 일정을 **읽기 전용**으로 월별 달력에 표시합니다. 앱의 Supabase 로그인 계정과는 별개이며 일정 본문을 Supabase에 저장하지 않습니다. Google Cloud OAuth 설정이 번거롭다면 Mac **시스템 설정 → 인터넷 계정**에 Google 계정을 연결한 뒤 앱의 **Mac 캘린더 읽기 허용** 기능을 사용할 수 있습니다.

1. [Google Cloud Console](https://console.cloud.google.com/apis/credentials)에서 이 앱에 사용할 프로젝트를 선택하거나 만듭니다. 프로젝트에서 **Google Calendar API**를 사용 설정합니다.
2. Google Auth Platform에서 동의 화면의 앱 이름, 지원 이메일과 대상 사용자를 설정합니다. 필요한 권한 범위는 `https://www.googleapis.com/auth/calendar.calendarlist.readonly`와 `https://www.googleapis.com/auth/calendar.events.readonly`입니다. 테스트 상태라면 접속할 Google 계정을 테스트 사용자에 추가합니다.
3. OAuth 클라이언트 ID를 **데스크톱 앱** 유형으로 만듭니다. 표시되는 **Client ID**만 복사합니다. Client Secret은 앱에 입력하거나 공개 저장소에 넣지 않습니다.
4. monthly-plan의 **계정 · 동기화 → Google 계정으로 직접 연결**에 Client ID를 붙여 넣고 연결 버튼을 누릅니다. 기본 브라우저에서 로그인과 읽기 권한을 허용하면 앱으로 돌아옵니다. 표시할 캘린더에 체크하세요.

다른 Mac에서도 각 Mac의 앱에서 연결해야 합니다. 접근·갱신 토큰은 연결한 Mac의 키체인에만 저장되며, 연결 해제 시 삭제됩니다. Google Cloud의 외부 앱이 **Testing** 상태면 일부 권한의 갱신 토큰은 7일 뒤 만료될 수 있어 재연결이 필요합니다. 일반 사용자에게 공개하려면 Google의 민감한 범위 검증이 필요할 수 있습니다. 같은 캘린더를 Mac 캘린더 방식과 직접 연결 방식에서 모두 선택하면 중복 표시됩니다.

참고: [데스크톱 앱 OAuth](https://developers.google.com/identity/protocols/oauth2/native-app), [Calendar API 권한 범위](https://developers.google.com/workspace/calendar/api/auth), [OAuth 게시 상태](https://developers.google.com/identity/protocols/oauth2)
