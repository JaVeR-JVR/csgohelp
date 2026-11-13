SHELL := /bin/bash
SWIFT ?= swift
PYTHON ?= python3
APP_NAME := CSGOHelper
BUILD_DIR := build
APP := $(BUILD_DIR)/$(APP_NAME).app
BINARY := .build/release/csgo-helper
INSTALL_DIR := $(HOME)/Applications
INSTALL_APP := $(INSTALL_DIR)/$(APP_NAME).app
LAUNCH_AGENT_DIR := $(HOME)/Library/LaunchAgents
LAUNCH_AGENT := $(LAUNCH_AGENT_DIR)/local.csgo.helper.plist
CONFIG_DIR := $(HOME)/Library/Application Support/CSGOHelper
CONFIG := $(CONFIG_DIR)/config.json
LOG_DIR := $(HOME)/Library/Logs/CSGOHelper
WRAPPER := $(INSTALL_DIR)/csgo-helper-steam.sh
UID := $(shell id -u)

.PHONY: all app build patterns test selftest check lint run run-headless install uninstall steam-wrapper purge clean distclean

all: app

patterns:
	@$(PYTHON) Tools/build_patterns.py

app: patterns
	@mkdir -p "$(APP)/Contents/MacOS" "$(APP)/Contents/Resources"
	$(SWIFT) build -c release --product csgo-helper
	@cp "$(BINARY)" "$(APP)/Contents/MacOS/csgo-helper"
	@cp Resources/Info.plist "$(APP)/Contents/Info.plist"
	@cp Resources/patterns.json "$(APP)/Contents/Resources/patterns.json"
	@cp Config/config.example.json "$(APP)/Contents/Resources/config.example.json"
	@cp THIRD_PARTY_NOTICES.md "$(APP)/Contents/Resources/THIRD_PARTY_NOTICES.md"
	@cp scripts/steam-launch-wrapper.sh "$(APP)/Contents/Resources/steam-launch-wrapper.sh"
	@chmod +x "$(APP)/Contents/MacOS/csgo-helper" "$(APP)/Contents/Resources/steam-launch-wrapper.sh"
	@plutil -lint "$(APP)/Contents/Info.plist" >/dev/null
	@codesign --force --deep --sign - "$(APP)" >/dev/null 2>&1 || \
		echo "предупреждение: ad-hoc codesign не удался; TCC может работать, но разрешения могут сброситься" >&2
	@echo "Собрано: $(APP)"
	@echo "Запуск:  open $(APP)"
	@echo "Проверка: $(APP)/Contents/MacOS/csgo-helper --selftest"

build: app

test:
	$(SWIFT) test

selftest: app
	"$(APP)/Contents/MacOS/csgo-helper" --patterns "$(CURDIR)/Resources/patterns.json" --selftest

check: lint test selftest
	@echo "Все проверки пройдены."

lint:
	@plutil -lint Resources/Info.plist LaunchAgents/local.csgo.helper.plist >/dev/null
	@bash -n scripts/steam-launch-wrapper.sh
	@$(PYTHON) -m py_compile Tools/build_patterns.py Tools/extract_game_data.py
	@echo "lint: OK"

run: app
	@open "$(APP)"

run-headless: app
	"$(APP)/Contents/MacOS/csgo-helper" --headless --patterns "$(CURDIR)/Resources/patterns.json"

install: app
	@mkdir -p "$(INSTALL_DIR)" "$(CONFIG_DIR)" "$(LOG_DIR)" "$(LAUNCH_AGENT_DIR)"
	@launchctl bootout gui/$(UID)/local.csgo.helper 2>/dev/null || true
	@-pkill -f "$(INSTALL_APP)/Contents/MacOS/csgo-helper" 2>/dev/null || true
	@rm -rf "$(INSTALL_APP)"
	@cp -R "$(APP)" "$(INSTALL_APP)"
	@if [ ! -f "$(CONFIG)" ]; then cp Config/config.example.json "$(CONFIG)"; fi
	@sed -e 's|__APP__|$(INSTALL_APP)|g' \
	     -e 's|__CONFIG__|$(CONFIG)|g' \
	     -e 's|__CONFIG_DIR__|$(CONFIG_DIR)|g' \
	     -e 's|__LOG_DIR__|$(LOG_DIR)|g' \
	     LaunchAgents/local.csgo.helper.plist > "$(LAUNCH_AGENT)"
	@cp scripts/steam-launch-wrapper.sh "$(WRAPPER)"
	@chmod +x "$(WRAPPER)"
	@launchctl bootstrap gui/$(UID) "$(LAUNCH_AGENT)"
	@launchctl enable gui/$(UID)/local.csgo.helper 2>/dev/null || true
	@launchctl kickstart -k gui/$(UID)/local.csgo.helper 2>/dev/null || true
	@echo "Установлено: $(INSTALL_APP)"
	@echo "LaunchAgent: $(LAUNCH_AGENT)"
	@echo "Конфиг:     $(CONFIG)"
	@echo "Steam-обёртка: $(WRAPPER)"
	@echo ""
	@echo "Выдайте Accessibility и Input Monitoring для:"
	@echo "  $(INSTALL_APP)"
	@echo "Затем: launchctl kickstart -k gui/$(UID)/local.csgo.helper"

steam-wrapper: app
	@mkdir -p "$(INSTALL_DIR)"
	@cp scripts/steam-launch-wrapper.sh "$(WRAPPER)"
	@chmod +x "$(WRAPPER)"
	@echo "Steam-обёртка: $(WRAPPER)"
	@echo "Launch options: $(WRAPPER) %command%"

uninstall:
	@launchctl bootout gui/$(UID)/local.csgo.helper 2>/dev/null || true
	@-pkill -f "$(INSTALL_APP)/Contents/MacOS/csgo-helper" 2>/dev/null || true
	@rm -f "$(LAUNCH_AGENT)" "$(WRAPPER)"
	@rm -rf "$(INSTALL_APP)"
	@echo "LaunchAgent и установленное приложение удалены."
	@echo "Конфиг и логи сохранены: $(CONFIG), $(LOG_DIR)"

purge: uninstall
	@rm -rf "$(CONFIG_DIR)" "$(LOG_DIR)"
	@echo "Конфиг и логи удалены."

clean:
	@rm -rf "$(BUILD_DIR)"
	@$(SWIFT) package clean
	@echo "build/ и .build/ очищены."

distclean: clean purge
