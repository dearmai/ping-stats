# PingStats for Rocky Linux / GNOME

Rocky Linux 9.8, GNOME Shell 40을 기준으로 한 Linux 데스크톱 앱입니다.
시스템 Python 3.9, GTK 3, PyGObject, Cairo를 사용합니다. macOS 앱은 기존
`Sources/PingStats/`에서 별도로 유지합니다. pip 패키지는 필요하지 않습니다.

## 실행과 설치

저장소 루트에서 실행합니다.

```sh
sudo dnf install python3 python3-gobject python3-cairo gtk3 iputils iproute libappindicator-gtk3
make linux-run
```

다른 폴더에서 실행할 때는 프로젝트 경로를 지정하세요.

```sh
make -C /work/ping-stats linux-install
make -C /work/ping-stats linux-run
```

`libayatana-appindicator-gtk3`도 지원합니다. 추가 저장소가 필요한 패키지는 해당
시스템의 패키지 정책에 맞춰 설치하세요. 개발 기준 시스템에는 GTK와 두 indicator
라이브러리 모두 설치되어 있습니다.

상단 아이콘에는 [GNOME AppIndicator 확장](https://extensions.gnome.org/extension/615/appindicator-support/)이
필요합니다. GNOME Shell 40과 호환되는 버전을 사용하세요. 설치된 확장은 다음으로 확인하고 활성화합니다.

```sh
gnome-extensions list
gnome-extensions enable appindicatorsupport@rgcjonas.gmail.com
```

확장이 없어도 앱 목록에서 모니터 창을 열 수 있습니다. 아이콘을 클릭하면 대상별 상태가
보이는 메뉴가 열리고, 차트·모니터·설정·종료를 선택합니다. 창을 닫으면 검사는
백그라운드에서 계속됩니다. 완전한 종료는 창 또는 아이콘 메뉴의 **종료**를 사용합니다.

```sh
make linux-install
```

현재 사용자의 `$XDG_DATA_HOME/pingstats`(기본 `~/.local/share/pingstats`)에 코드를
복사하고 `applications/dev.pingstats.app.desktop`을 등록합니다. GNOME 앱 목록에서
**PingStats**를 실행할 수 있습니다. 개발 후 다시 설치하면 설치본이 갱신됩니다.
자동 시작은 설치 후 설정의 **로그인 시 실행**을 켜면 즉시 적용되며 기본은 꺼짐입니다.

## 구현된 기능

- 여러 대상 추가·삭제·사용 여부, 대상별 경고/오류 알림 설정.
- 호스트/IP는 ICMP, `host:port`와 `[IPv6]:port`는 TCP 연결 시간 측정.
  포트 없는 IPv6 주소도 ICMP로 지원.
- `http://`·`https://`는 GET 요청, 리디렉션을 따라가며 최종 2xx/3xx는 성공.
  TLS 인증서를 검증하고 본문 수신까지 시간을 측정.
- 창 표시 중 기본 1초 주기/1초 제한, 숨김 상태에서는 5초 주기/3초 제한.
  프로세스 시작 여유 0.3초를 포함한 외부 제한으로 DNS·느린 HTTP 응답도 종료.
  최대 16개 병렬 검사, 같은 대상에 검사를 중복 실행하지 않음.
- 최근 10건 평균·최근 응답, 대상별 2열 차트와 오류 표시, 현재 시각.
  차트 기간은 실제 Swift 기본값과 같은 10분이며 1~60분으로 설정 가능.
- 아이콘 클릭 한 번에 대상별 상태 점·문자 차트·최근/평균 응답이 메뉴에 표시되고,
  대상 줄이나 **차트**를 고르면 화면 오른쪽 위에 간략 차트 레이어가 열립니다.
- 기존과 같은 회색/초록/파랑/노랑/주황/빨강 상태와 알림 전환 규칙.
- 활성 인터페이스의 IPv4/IPv6 주소 표시와 클릭 복사. loopback/link-local 제외.
- JSON 설정 저장·가져오기·내보내기, 한국어/영어 UI, GNOME 데스크톱 알림.

설정은 `$XDG_CONFIG_HOME/pingstats/settings.json`(기본 `~/.config/pingstats/settings.json`)에
원자적으로 저장합니다. 설정 필드명은 Swift `PingSettings`와 맞췄으며 macOS
UserDefaults에서 추출한 현재 형식 JSON을 가져올 수 있습니다. 손상된 설정은
덮어쓰지 않고 오류를 표시합니다. macOS UserDefaults 자동 이전은 제공하지 않습니다.

## GNOME에서 달라지는 부분

### 표시 언어

한국어 시스템과 언어가 지정되지 않은 `C`/`C.UTF-8` 환경에서는 한국어로 표시합니다.
영어 시스템에서는 영어를 사용합니다. `LANGUAGE`에 지원 언어가 있으면 우선 적용하며,
`PINGSTATS_LANGUAGE`로 앱 언어를 명시적으로 선택할 수 있습니다.

```sh
PINGSTATS_LANGUAGE=ko make linux-run
PINGSTATS_LANGUAGE=en make linux-run
```

언어를 바꿀 때는 실행 중인 PingStats를 **종료**한 뒤 다시 실행하세요.
앱 메뉴·설정·알림·차트 시간 단위와 앱 자체 오류 안내를 번역합니다.
운영체제와 네트워크 라이브러리의 상세 오류는 진단을 위해 원문을 보존하며,
파일 선택기 내부의 기본 항목은 시스템 GTK 언어 설정에 따릅니다.

### 화면과 시스템 연동

상단 아이콘은 GNOME이 할당하는 정사각형 영역에 호스트별 색상 막대를 그립니다.
10개부터 2행이며 대상이 많으면 막대가 작아집니다. macOS처럼 아이콘 폭이 늘어나지는 않습니다.

아이콘을 클릭하면 GNOME이 그리는 메뉴만 열 수 있고, 그 메뉴는 확장이 DBus로 받은
글자와 작은 아이콘만 그리므로 macOS 팝오버 그림을 그대로 넣을 수 없습니다. 대신 메뉴
맨 위에 대상마다 `🟢 Cloudflare  ▂▃▂▄▂  10 ms · 평균 11 ms` 형태로 상태 점과 최근 응답을
막대 문자 차트로 보여 줍니다. 문자 차트의 눈금은 파랑 임계값까지를 기준으로 하되 제곱근
눈금이라 정상 구간의 흔들림도 모양이 남고, 실패한 검사는 `×`로 표시합니다.

대상 줄이나 **차트**를 선택하면 그림 차트를 그리는 간략 차트 레이어(GTK 창)가 열립니다.
GNOME은 아이콘 위치를 알려주지 않으므로 상단 막대 아래 화면 오른쪽 위에 붙이며,
Esc를 누르거나 다른 창을 누르면 닫힙니다. 전체 창은 **모니터**로 엽니다.
레이어가 열려 있는 동안에는 창 표시 중과 같은 검사 주기를 사용합니다.

아이콘은 상태가 바뀔 때 즉시 갱신하며, 색상 조합별 SVG 경로를 사용해 GNOME의
아이콘 캐시가 이전 색상을 표시하지 않도록 합니다. 정상 복귀 판정에는 최근 10회
연속 성공이 필요하므로 기본 검사 주기에서 창 표시 중 약 10초, 숨김 상태에서 약 50초가 걸립니다.
네트워크 이름은 `enp…`, `wlp…` 같은 Linux 인터페이스 이름을 표시합니다.
알림 노출과 소리는 GNOME 알림 설정 및 방해 금지 모드에 따릅니다.

검증 환경은 Rocky 9.8 / GNOME 40 / X11입니다. Wayland에서의 실제 표시,
알림 배너, 재로그인 자동 시작은 별도 수동 확인이 필요합니다.

## 검증

```sh
make linux-test
make linux-smoke  # 로그인한 GNOME 그래픽 세션 필요
```

단위/통합 테스트는 상태 경계값, 모든 상태 전환, 알림 필터, 설정 저장,
주소 해석, loopback ICMP/TCP/HTTP 및 HTTP 제한 시간, 트레이 메뉴의 문자 차트를 확인합니다.
`../shared/health-cases.json`은 기존 Swift 규칙에서 옮긴 공통 검증 데이터입니다.
Swift 테스트 실행과 자동 비교까지 연결된 상태는 아닙니다.
GUI 검증은 임시 설정과 loopback 대상으로 창·차트·트레이 메뉴 차트·간략 차트 레이어·설정·
아이콘 생성·창 숨김/재표시를 확인합니다.

설계 참고: [GTK Application](https://docs.gtk.org/gtk3/class.Application.html),
[GIO 데스크톱 알림](https://docs.gtk.org/gio/method.Application.send_notification.html).
