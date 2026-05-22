-include .env
export

APP_NAME := Freesper
BUNDLE_ID := com.freesper.app
CONFIG := Debug
DERIVED_DATA := $(PWD)/.build/derived
APP_PATH := $(DERIVED_DATA)/Build/Products/$(CONFIG)/$(APP_NAME).app
MODELS_DIR := $(HOME)/Library/Application Support/$(APP_NAME)/Models
DIST_DIR := $(PWD)/dist

.PHONY: install
install:
	mise install

.PHONY: prepare-xcodeproj
prepare-xcodeproj:
	tuist install
	tuist generate --no-open

.PHONY: open-xcodeproj
open-xcodeproj: prepare-xcodeproj
	open $(APP_NAME).xcworkspace

.PHONY: build
build: prepare-xcodeproj
	tuist xcodebuild build \
		-workspace $(APP_NAME).xcworkspace \
		-scheme $(APP_NAME) \
		-configuration $(CONFIG) \
		-derivedDataPath $(DERIVED_DATA) \
		-destination 'platform=macOS,arch=arm64'

.PHONY: stop
stop:
	@if pkill -x $(APP_NAME); then \
		while pgrep -x $(APP_NAME) >/dev/null; do sleep 0.1; done; \
		echo "stopped"; \
	else \
		echo "not running"; \
	fi

.PHONY: dev
dev: build stop
	open "$(APP_PATH)"

.PHONY: preview-build
preview-build: prepare-xcodeproj
	tuist xcodebuild build \
		-workspace $(APP_NAME).xcworkspace \
		-scheme $(APP_NAME) \
		-configuration Release \
		-derivedDataPath $(DERIVED_DATA) \
		-destination 'platform=macOS,arch=arm64' \
		ARCHS=arm64 \
		CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM=
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

.PHONY: remove-model
remove-model: stop
	@if [ -d "$(MODELS_DIR)" ]; then \
		rm -rf "$(MODELS_DIR)"; \
		echo "removed $(MODELS_DIR)"; \
	else \
		echo "no model directory at $(MODELS_DIR)"; \
	fi

.PHONY: clean
clean:
	tuist clean
	rm -rf .build \
		Tuist/.build \
		$(APP_NAME).xcworkspace \
		$(APP_NAME).xcodeproj \
		Derived \
		$(DIST_DIR)
