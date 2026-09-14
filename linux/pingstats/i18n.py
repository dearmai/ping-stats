import os

def language(environ=None):
    environ = os.environ if environ is None else environ
    override = environ.get("PINGSTATS_LANGUAGE", "").lower()
    if override in ("ko", "en"):
        return override
    system = environ.get("LC_ALL") or environ.get("LC_MESSAGES") or environ.get("LANG", "C")
    # A neutral shell locale has no language preference; default to Korean.
    preferences = environ.get("LANGUAGE", "").split(":")
    for preference in preferences:
        code = preference.lower().split("_")[0].split("-")[0].split(".")[0]
        if code in ("ko", "en"):
            return code
    if system.upper() in ("C", "C.UTF-8", "C.UTF8", "POSIX"):
        return "ko"
    return "ko" if system.lower().startswith("ko") else "en"


KOREAN = language() == "ko"
TRANSLATIONS = {
    "Monitor": "모니터", "Settings": "설정", "Quit": "종료", "Check now": "지금 검사",
    "Save": "저장", "Cancel": "취소", "Add target": "대상 추가", "Remove": "삭제",
    "Name": "이름", "Address": "주소", "Enabled": "사용", "Warning": "경고", "Error": "오류",
    "Launch at login": "로그인 시 실행", "Import JSON": "JSON 가져오기", "Export JSON": "JSON 내보내기",
    "Background interval (s)": "백그라운드 검사 주기 (초)", "Background timeout (s)": "백그라운드 제한 시간 (초)",
    "Foreground interval (s)": "창 표시 중 검사 주기 (초)", "Foreground timeout (s)": "창 표시 중 제한 시간 (초)",
    "Chart window (s)": "차트 표시 기간 (초)", "Green threshold (ms)": "초록 임계값 (ms)",
    "Blue threshold (ms)": "파랑 임계값 (ms)", "No targets. Add one in Settings.": "설정에서 검사 대상을 추가하세요.",
    "Chart": "차트", "Average": "평균", "Close chart": "차트 닫기",
    "Local IP": "내 IP", "Copied": "복사됨", "Recovered": "복구됨", "Good": "좋음", "Normal": "정상",
    "Critical": "심각", "Unknown": "준비 중", "Latest": "최근", "Average (10)": "평균 (10건)",
    "Settings could not be loaded": "설정을 불러올 수 없습니다", "Close": "닫기",
    "Monitoring continues when this window is closed.": "창을 닫아도 검사를 계속합니다.",
    "Tray support requires the GNOME AppIndicator extension.": "상단 아이콘 표시는 GNOME AppIndicator 확장이 필요합니다.",
    "-%g min": "-%g분", "Installed": "설치 완료",
    "Settings must be a JSON object": "설정은 JSON 객체여야 합니다",
    "Targets must be an array": "검사 대상 목록은 배열이어야 합니다",
    "Invalid target": "검사 대상 형식이 올바르지 않습니다",
    "Target name and address must be text": "대상 이름과 주소는 문자열이어야 합니다",
    "Invalid target options": "검사 대상 옵션이 올바르지 않습니다",
    "Invalid number": "숫자 설정이 올바르지 않습니다",
    "Invalid address": "주소가 올바르지 않습니다",
    "Invalid HTTP URL": "HTTP 주소가 올바르지 않습니다",
    "Use host:port with a port from 1 to 65535": "호스트:포트 형식으로 입력하세요. 포트 범위는 1~65535입니다",
    "ping not found; install iputils": "ping을 찾을 수 없습니다. iputils 패키지를 설치하세요",
    "Ping failed": "Ping 검사에 실패했습니다", "Probe failed": "네트워크 검사에 실패했습니다",
    "Timeout": "응답 시간이 초과되었습니다",
    "Install PingStats before enabling autostart": "로그인 시 실행을 켜려면 먼저 PingStats를 설치하세요",
    "Could not read settings JSON": "설정 JSON을 읽을 수 없습니다",
    "File operation failed": "파일 작업에 실패했습니다",
}


def tr(text):
    return TRANSLATIONS.get(text, text) if KOREAN else text


def error_text(error):
    """Translate app-owned errors while retaining diagnostic details verbatim."""
    import json
    if isinstance(error, json.JSONDecodeError):
        return tr("Could not read settings JSON") + "\n" + str(error)
    if isinstance(error, OSError):
        return tr("File operation failed") + "\n" + str(error)
    text = str(error)
    if text.startswith("Invalid number: "):
        return tr("Invalid number") + ": " + text.partition(": ")[2]
    return tr(text)
