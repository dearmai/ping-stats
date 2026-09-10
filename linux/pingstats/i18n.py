import os

KOREAN = (os.environ.get("LC_ALL") or os.environ.get("LC_MESSAGES") or os.environ.get("LANG", "en")).startswith("ko")
TRANSLATIONS = {
    "Monitor": "모니터", "Settings": "설정", "Quit": "종료", "Check now": "지금 검사",
    "Save": "저장", "Cancel": "취소", "Add target": "대상 추가", "Remove": "삭제",
    "Name": "이름", "Address": "주소", "Enabled": "사용", "Warning": "경고", "Error": "오류",
    "Launch at login": "로그인 시 실행", "Import JSON": "JSON 가져오기", "Export JSON": "JSON 내보내기",
    "Background interval (s)": "백그라운드 검사 주기 (초)", "Background timeout (s)": "백그라운드 제한 시간 (초)",
    "Foreground interval (s)": "창 표시 중 검사 주기 (초)", "Foreground timeout (s)": "창 표시 중 제한 시간 (초)",
    "Chart window (s)": "차트 표시 기간 (초)", "Green threshold (ms)": "초록 임계값 (ms)",
    "Blue threshold (ms)": "파랑 임계값 (ms)", "No targets. Add one in Settings.": "설정에서 검사 대상을 추가하세요.",
    "Local IP": "내 IP", "Copied": "복사됨", "Recovered": "복구됨", "Good": "좋음", "Normal": "정상",
    "Critical": "심각", "Unknown": "준비 중", "Latest": "최근", "Average (10)": "평균 (10건)",
    "Settings could not be loaded": "설정을 불러올 수 없습니다", "Close": "닫기",
    "Monitoring continues when this window is closed.": "창을 닫아도 검사를 계속합니다.",
    "Tray support requires the GNOME AppIndicator extension.": "상단 아이콘 표시는 GNOME AppIndicator 확장이 필요합니다.",
}


def tr(text):
    return TRANSLATIONS.get(text, text) if KOREAN else text
