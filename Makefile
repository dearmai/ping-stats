APP_NAME := PingStats
APP_BUNDLE := build/$(APP_NAME).app
INSTALL_DIR := /Applications
INSTALLED_APP := $(INSTALL_DIR)/$(APP_NAME).app

.DEFAULT_GOAL := help

.PHONY: linux-run linux-install linux-test linux-smoke
linux-run: ## Linux GTK 앱 실행
	/usr/bin/python3 linux/pingstats-linux

linux-install: ## Linux 앱을 현재 사용자 계정에 설치
	/usr/bin/python3 linux/install.py

linux-test: ## Linux 상태 규칙·설정·네트워크 검사 테스트
	PYTHONPATH=linux /usr/bin/python3 -m unittest discover -s linux/tests -v

linux-smoke: ## Linux 그래픽 세션에서 UI 검증
	/usr/bin/python3 linux/tests/smoke_gui.py

.PHONY: help
help: ## 지원하는 명령 목록 표시
	@echo "$(APP_NAME) - 사용 가능한 make 명령:"
	@echo ""
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
		| awk 'BEGIN {FS = ":.*?## "} {printf "  \033[36m%-12s\033[0m %s\n", $$1, $$2}'
	@echo ""

.PHONY: build
build: ## 릴리스 바이너리 빌드 (swift build -c release)
	swift build -c release

.PHONY: app
app: ## .app 번들 생성 (build/PingStats.app)
	scripts/build-app.sh

.PHONY: sign
sign: app ## self-signed 코드 서명
	scripts/sign-self-signed.sh

.PHONY: install
install: app ## 빌드 후 /Applications 에 설치
	rm -rf "$(INSTALLED_APP)"
	cp -R "$(APP_BUNDLE)" "$(INSTALLED_APP)"
	@echo "설치 완료: $(INSTALLED_APP)"

.PHONY: uninstall
uninstall: ## /Applications 에서 제거
	rm -rf "$(INSTALLED_APP)"
	@echo "제거 완료: $(INSTALLED_APP)"

.PHONY: clean
clean: ## 빌드 산출물 삭제
	swift package clean
	rm -rf build
	@echo "정리 완료"
