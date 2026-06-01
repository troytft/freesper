-include .env
export

APP_NAME := Freesper
BUNDLE_ID := me.troytft.freesper.dev
DERIVED_DATA := $(PWD)/.build/derived
MODELS_DIR := $(HOME)/Library/Application Support/$(APP_NAME)/Models
DIST_DIR := $(PWD)/dist

XCODEBUILD = tuist xcodebuild build \
	-workspace $(APP_NAME).xcworkspace \
	-scheme $(APP_NAME) \
	-derivedDataPath $(DERIVED_DATA) \
	-destination 'platform=macOS,arch=arm64'

RELEASE_DIR := $(PWD)/.build/release
ARCHIVE_PATH := $(RELEASE_DIR)/$(APP_NAME).xcarchive
EXPORT_DIR := $(RELEASE_DIR)/export
EXPORT_OPTIONS := $(RELEASE_DIR)/ExportOptions.plist
APP_PATH := $(EXPORT_DIR)/$(APP_NAME).app
APP_ZIP := $(RELEASE_DIR)/$(APP_NAME).zip
DMG_STAGING := $(RELEASE_DIR)/dmg
DMG_PATH := $(DIST_DIR)/$(APP_NAME)-$(VERSION).dmg

CODE_SIGN_IDENTITY ?= Developer ID Application

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

.PHONY: release
release:
	@test -n "$(VERSION)" || { echo "VERSION is required (make release VERSION=x.y.z)"; exit 1; }
	@test -n "$(NOTARY_KEY)" || { echo "NOTARY_KEY is not set — add it to .env"; exit 1; }
	@test -n "$(NOTARY_KEY_ID)" || { echo "NOTARY_KEY_ID is not set — add it to .env"; exit 1; }
	@test -n "$(NOTARY_ISSUER)" || { echo "NOTARY_ISSUER is not set — add it to .env"; exit 1; }
	@test -n "$(SPARKLE_ED_KEY)" || { echo "SPARKLE_ED_KEY is not set — add it to .env"; exit 1; }
	$(MAKE) _release-archive
	$(MAKE) _release-app
	$(MAKE) _release-dmg
	$(MAKE) _release-appcast

.PHONY: _release-archive
_release-archive:
	rm -rf $(ARCHIVE_PATH)
	TUIST_VERSION=$(VERSION) TUIST_CODE_SIGN_IDENTITY="$(CODE_SIGN_IDENTITY)" $(MAKE) generate-xcodeproj
	tuist xcodebuild archive \
		-workspace $(APP_NAME).xcworkspace \
		-scheme $(APP_NAME) \
		-configuration Release \
		-destination 'generic/platform=macOS' \
		-archivePath $(ARCHIVE_PATH) \
		ARCHS=arm64 ONLY_ACTIVE_ARCH=NO

.PHONY: _release-app
_release-app:
	rm -rf $(EXPORT_DIR) $(EXPORT_OPTIONS) $(APP_ZIP)
	cp ExportOptions.plist $(EXPORT_OPTIONS)
	/usr/libexec/PlistBuddy -c "Add :teamID string $(TUIST_DEVELOPMENT_TEAM)" $(EXPORT_OPTIONS)
	xcodebuild -exportArchive \
		-archivePath $(ARCHIVE_PATH) \
		-exportPath $(EXPORT_DIR) \
		-exportOptionsPlist $(EXPORT_OPTIONS)
	ditto -c -k --keepParent $(APP_PATH) $(APP_ZIP)
	xcrun notarytool submit $(APP_ZIP) --key "$(NOTARY_KEY)" --key-id $(NOTARY_KEY_ID) --issuer $(NOTARY_ISSUER) --wait
	xcrun stapler staple $(APP_PATH)

.PHONY: _release-dmg
_release-dmg:
	rm -rf $(DIST_DIR) $(DMG_STAGING)
	mkdir -p $(DIST_DIR) $(DMG_STAGING)
	cp -R $(APP_PATH) $(DMG_STAGING)/
	ln -s /Applications $(DMG_STAGING)/Applications
	hdiutil create -volname "$(APP_NAME)" -srcfolder $(DMG_STAGING) -ov -format UDZO $(DMG_PATH)
	codesign --force --timestamp --sign "$(CODE_SIGN_IDENTITY)" $(DMG_PATH)
	xcrun notarytool submit $(DMG_PATH) --key "$(NOTARY_KEY)" --key-id $(NOTARY_KEY_ID) --issuer $(NOTARY_ISSUER) --wait
	xcrun stapler staple $(DMG_PATH)

.PHONY: _release-appcast
_release-appcast:
	generate_appcast $(DIST_DIR) --ed-key-file "$(SPARKLE_ED_KEY)" --download-url-prefix https://github.com/troytft/freesper/releases/download/v$(VERSION)/

.PHONY: tag-patch
tag-patch:
	@swift scripts/create-tag.swift patch

.PHONY: tag-minor
tag-minor:
	@swift scripts/create-tag.swift minor

.PHONY: tag-major
tag-major:
	@swift scripts/create-tag.swift major

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
