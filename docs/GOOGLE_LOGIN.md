# Google 계정으로 앱 로그인

이 로그인은 **Supabase에 저장된 monthly-plan 일정 계정**을 여는 기능입니다. Google Calendar 일정 읽기 권한은 요청하지 않습니다. 캘린더를 직접 읽으려면 [별도 안내](GOOGLE_CALENDAR.md)를 따르세요.

1. [Google Cloud Console](https://console.cloud.google.com/apis/credentials)에서 이 앱에 사용할 프로젝트를 선택하거나 만듭니다. OAuth 동의 화면의 앱 이름, 지원 이메일, 대상 사용자를 설정합니다. 테스트 상태라면 로그인할 Google 계정을 테스트 사용자에 추가합니다.
2. **OAuth 클라이언트 ID**를 **웹 애플리케이션** 유형으로 만듭니다. 승인된 리디렉션 URI에 `https://<SUPABASE_PROJECT_REF>.supabase.co/auth/v1/callback`을 입력합니다. 이 주소는 Google에서 Supabase로 돌아오는 주소이며 Mac 앱의 주소와 다릅니다.
3. [Supabase Auth → Providers → Google](https://supabase.com/dashboard/project/_/auth/providers)에서 Google 공급자를 켜고 웹 클라이언트 ID와 보안 비밀을 입력·저장합니다. **보안 비밀은 앱이나 GitHub에 넣지 않습니다.**
4. Supabase **Auth → URL Configuration → Redirect URLs**에 `monthly-plan://auth/callback?state=*`가 등록되어 있는지 확인합니다. 이 주소는 Supabase에서 Mac 앱으로 돌아오는 주소입니다.
5. monthly-plan의 **계정 · 동기화**에서 Supabase 프로젝트 URL과 **publishable/anon 키**를 연결한 뒤 **Google 계정으로 로그인**을 누릅니다. 브라우저 로그인을 마치면 앱으로 돌아와 해당 계정의 일정을 엽니다.

로그인한 Google 계정과 이전 이메일 로그인 계정의 주소가 다르면 각각 별도의 일정 저장소가 열립니다. 다른 계정의 자료를 자동으로 합치지 않습니다. Google 로그인이 실패하면 Google Cloud의 OAuth 동의 화면·테스트 사용자, Supabase의 Google 공급자, 두 리디렉션 주소를 순서대로 확인하세요.

참고: [Supabase Google 로그인 설정](https://supabase.com/docs/guides/auth/social-login/auth-google), [Supabase 리디렉션 주소](https://supabase.com/docs/guides/auth/redirect-urls)
