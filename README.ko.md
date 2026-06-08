# PingStats

PingStats는 macOS 메뉴바에서 동작하는 네이티브 앱입니다. 등록한 호스트로 주기적으로 ping을 보내고, 각 호스트의 상태를 메뉴바의 세로 컬러 바로 표시합니다.

[English README](README.md)

## 주요 기능

- 설정 창에서 여러 호스트 등록.
- 백그라운드 ping 검사: 기본 주기 5초, 타임아웃 3초.
- 팝오버가 열린 동안 포어그라운드 ping 검사: 기본 주기 1초, 타임아웃 1초.
- 호스트별 메뉴바 상태 색상:
  - 초록: 최근 10건 평균 50 ms 미만.
  - 파랑: 최근 10건 평균 100 ms 미만.
  - 노랑: 최근 10건 평균 200 ms 미만, 200 ms 이상, 또는 최근 10건 데이터 부족.
  - 주황: 최근 10건 중 타임아웃 또는 네트워크 오류 1건 이상.
  - 빨강: 최근 5건 중 오류 4건 이상.
- 알림 조건:
  - 정상 상태인 초록/파랑에서 노랑/주황/빨강으로 전환될 때.
  - 노랑/주황/빨강 사이에서 단계가 변경될 때.
  - 초록과 파랑 사이의 정상 범주 전환은 알림 없음.
- 메뉴바 클릭 시 2열 차트 팝오버 표시.
- 팝오버에서 현재 시간(`HH:mm:ss`)과 최근 5분 응답 시간 추이를 표시.

## 빌드

이 프로젝트는 외부 의존성 없이 Swift Package Manager를 사용합니다.

```sh
swift build
swift run PingStats
```

메뉴바 `.app` 번들을 만들려면:

```sh
chmod +x scripts/build-app.sh
scripts/build-app.sh
open build/PingStats.app
```

## 셀프 서명 배포 패키지

로컬 셀프 서명 코드서명 인증서로 앱을 서명하고 zip 패키지를 만들려면:

```sh
scripts/sign-self-signed.sh
```

셀프 서명 인증서가 아직 코드서명용으로 신뢰되지 않았다면 명시적으로 로컬 신뢰 설정을 추가해야 합니다.

```sh
scripts/sign-self-signed.sh --trust-local
```

이 명령은 로그인 키체인의 trust 설정을 변경합니다. 스크립트는 `dist/PingStats.zip`과 `dist/PingStatsSelfSigned.cer`를 생성합니다.

다른 Mac에서는 셀프 서명 인증서가 자동으로 신뢰되지 않습니다. 최초 실행 시 Control-click > Open을 사용하거나, `dist/PingStatsSelfSigned.cer`를 키체인 접근 앱에 가져온 뒤 코드서명용으로 신뢰해야 합니다.

## Xcode 툴체인 검증

`swift build`가 SDK/compiler mismatch 오류로 실패하면 Xcode 또는 Command Line Tools 설정을 확인합니다.

```sh
xcode-select --install
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
```

Xcode 설치 후 아래 스크립트로 툴체인 전환과 프로젝트 빌드를 검증할 수 있습니다.

```sh
scripts/verify-xcode-toolchain.sh
```

## GitHub Actions

`.github/workflows/desktop-macos-ci.yml`은 `v*` 태그 push 또는 수동 실행 시 동작합니다.

- self-hosted macOS ARM64 러너에서 빌드.
- SwiftPM manifest 검증.
- `.app` 번들 생성.
- 셀프 서명 및 zip 패키지 생성.
- artifact 업로드.
- 태그 빌드인 경우 GitHub Release에 산출물 첨부.

현재 구현은 메뉴바 상태 아이템에 AppKit을 사용하고, 팝오버와 설정 화면에는 SwiftUI를 사용합니다.
