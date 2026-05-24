-include .env
export

APP_NAME := Freesper
BUNDLE_ID := com.freesper.app
DERIVED_DATA := $(PWD)/.build/derived
MODELS_DIR := $(HOME)/Library/Application Support/$(APP_NAME)/Models
DIST_DIR := $(PWD)/dist

XCODEBUILD = tuist xcodebuild build \
	-workspace $(APP_NAME).xcworkspace \
	-scheme $(APP_NAME) \
	-derivedDataPath $(DERIVED_DATA) \
	-destination 'platform=macOS,arch=arm64'

.PHONY: install
install:
	mise install

.PHONY: generate-xcodeproj
generate-xcodeproj:
	tuist install
	tuist generate --no-open

.PHONY: open-xcode
open-xcode: generate-xcodeproj
	open $(APP_NAME).xcworkspace

.PHONY: build-debug
build-debug: generate-xcodeproj
	$(XCODEBUILD) -configuration Debug

.PHONY: build-release
build-release: generate-xcodeproj
	$(XCODEBUILD) -configuration Release ARCHS=arm64 CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM=

.PHONY: stop
stop:
	@if pkill -x $(APP_NAME); then \
		while pgrep -x $(APP_NAME) >/dev/null; do sleep 0.1; done; \
		echo "stopped"; \
	else \
		echo "not running"; \
	fi

.PHONY: dev
dev: build-debug stop
	open "$(DERIVED_DATA)/Build/Products/Debug/$(APP_NAME).app"

.PHONY: preview-build
preview-build: build-release
	rm -rf "$(DIST_DIR)" && mkdir -p "$(DIST_DIR)"
	ditto -c -k --keepParent \
		"$(DERIVED_DATA)/Build/Products/Release/$(APP_NAME).app" \
		"$(DIST_DIR)/$(APP_NAME).zip"
	@echo "ready: $(DIST_DIR)/$(APP_NAME).zip"

.PHONY: logs
logs:
	/usr/bin/log stream --level debug --predicate 'subsystem == "$(BUNDLE_ID)" OR process == "$(APP_NAME)"'

.PHONY: fmt
fmt:
	swift-format format -i -r Sources

.PHONY: lint
lint:
	swift-format lint --strict -r Sources

.PHONY: dead-code
dead-code: generate-xcodeproj
	periphery scan --strict

.PHONY: wipe-models
wipe-models:
	@if [ -d "$(MODELS_DIR)" ]; then \
		rm -rf "$(MODELS_DIR)"; \
		echo "removed $(MODELS_DIR)"; \
	else \
		echo "no model directory at $(MODELS_DIR)"; \
	fi

.PHONY: wipe-prefs
wipe-prefs:
	@if defaults delete $(BUNDLE_ID) 2>/dev/null; then \
		echo "cleared preferences"; \
	else \
		echo "no preferences to clear"; \
	fi

.PHONY: wipe-permissions
wipe-permissions:
	@tccutil reset Microphone $(BUNDLE_ID) >/dev/null 2>&1 \
		&& echo "reset microphone permission" \
		|| echo "no microphone permission to reset"
	@tccutil reset Accessibility $(BUNDLE_ID) >/dev/null 2>&1 \
		&& echo "reset accessibility permission" \
		|| echo "no accessibility permission to reset"

.PHONY: wipe
wipe: stop wipe-models wipe-prefs wipe-permissions

.PHONY: clean
clean:
	tuist clean
	rm -rf .build \
		Tuist/.build \
		$(APP_NAME).xcworkspace \
		$(APP_NAME).xcodeproj \
		Derived \
		$(DIST_DIR)
