APP_NAME = Autoclaw
BUNDLE_ID = com.autoclaw.app
BUILD_DIR = build
APP_BUNDLE = $(BUILD_DIR)/$(APP_NAME).app
CONTENTS = $(APP_BUNDLE)/Contents
MACOS_DIR = $(CONTENTS)/MacOS
RESOURCES = $(CONTENTS)/Resources

ARCH = $(shell uname -m)

.PHONY: all clean run spm legacy dmg

# Default: SPM build (with WhisperKit)
all: spm

# SPM build — uses Package.swift, includes WhisperKit + all dependencies
spm:
	@mkdir -p "$(MACOS_DIR)" "$(RESOURCES)"
	swift build -c release 2>&1
	@cp ".build/release/$(APP_NAME)" "$(MACOS_DIR)/$(APP_NAME)"
	@cp Info.plist "$(CONTENTS)/"
	@plutil -replace CFBundleExecutable -string "$(APP_NAME)" "$(CONTENTS)/Info.plist"
	@plutil -replace CFBundleIdentifier -string "$(BUNDLE_ID)" "$(CONTENTS)/Info.plist"
	@if [ -f Resources/AppIcon.icns ]; then cp Resources/AppIcon.icns "$(RESOURCES)/"; fi
	@cp -f Resources/menubar_icon.png Resources/menubar_icon@2x.png Resources/logo_40.png "$(RESOURCES)/" 2>/dev/null || true
	@cp -f Resources/menubar_icon_green.png Resources/menubar_icon_green@2x.png "$(RESOURCES)/" 2>/dev/null || true
	@cp -f Resources/menubar_icon_paused.png Resources/menubar_icon_paused@2x.png "$(RESOURCES)/" 2>/dev/null || true
	@cp -f Resources/freepik__remove-background__60858.png "$(RESOURCES)/autoclaw_logo.png" 2>/dev/null || true
	@cp -f Resources/question_context.md "$(RESOURCES)/" 2>/dev/null || true
	@xattr -cr "$(APP_BUNDLE)" 2>/dev/null || true
	@codesign --force --sign - --entitlements Autoclaw.entitlements "$(APP_BUNDLE)"
	@echo "Built $(APP_BUNDLE) (SPM + WhisperKit)"

# Legacy build — pure swiftc, no external dependencies (fallback)
legacy:
	@mkdir -p "$(MACOS_DIR)" "$(RESOURCES)"
	swiftc \
		-parse-as-library \
		-sdk $(shell xcrun --show-sdk-path) \
		-target $(ARCH)-apple-macosx14.0 \
		-DLEGACY_BUILD \
		-o "$(MACOS_DIR)/$(APP_NAME)" \
		$(shell find Sources -name '*.swift' ! -name 'WhisperKitService.swift')
	@cp Info.plist "$(CONTENTS)/"
	@plutil -replace CFBundleExecutable -string "$(APP_NAME)" "$(CONTENTS)/Info.plist"
	@plutil -replace CFBundleIdentifier -string "$(BUNDLE_ID)" "$(CONTENTS)/Info.plist"
	@if [ -f Resources/AppIcon.icns ]; then cp Resources/AppIcon.icns "$(RESOURCES)/"; fi
	@cp -f Resources/menubar_icon.png Resources/menubar_icon@2x.png Resources/logo_40.png "$(RESOURCES)/" 2>/dev/null || true
	@cp -f Resources/menubar_icon_green.png Resources/menubar_icon_green@2x.png "$(RESOURCES)/" 2>/dev/null || true
	@cp -f Resources/menubar_icon_paused.png Resources/menubar_icon_paused@2x.png "$(RESOURCES)/" 2>/dev/null || true
	@cp -f Resources/freepik__remove-background__60858.png "$(RESOURCES)/autoclaw_logo.png" 2>/dev/null || true
	@cp -f Resources/question_context.md "$(RESOURCES)/" 2>/dev/null || true
	@xattr -cr "$(APP_BUNDLE)" 2>/dev/null || true
	@codesign --force --sign - --entitlements Autoclaw.entitlements "$(APP_BUNDLE)"
	@echo "Built $(APP_BUNDLE) (legacy, no WhisperKit)"

# Debug build (faster iteration)
debug:
	swift build 2>&1
	@mkdir -p "$(MACOS_DIR)" "$(RESOURCES)"
	@cp ".build/debug/$(APP_NAME)" "$(MACOS_DIR)/$(APP_NAME)"
	@cp Info.plist "$(CONTENTS)/"
	@plutil -replace CFBundleExecutable -string "$(APP_NAME)" "$(CONTENTS)/Info.plist"
	@plutil -replace CFBundleIdentifier -string "$(BUNDLE_ID)" "$(CONTENTS)/Info.plist"
	@if [ -f Resources/AppIcon.icns ]; then cp Resources/AppIcon.icns "$(RESOURCES)/"; fi
	@cp -f Resources/menubar_icon.png Resources/menubar_icon@2x.png Resources/logo_40.png "$(RESOURCES)/" 2>/dev/null || true
	@cp -f Resources/menubar_icon_green.png Resources/menubar_icon_green@2x.png "$(RESOURCES)/" 2>/dev/null || true
	@cp -f Resources/menubar_icon_paused.png Resources/menubar_icon_paused@2x.png "$(RESOURCES)/" 2>/dev/null || true
	@cp -f Resources/freepik__remove-background__60858.png "$(RESOURCES)/autoclaw_logo.png" 2>/dev/null || true
	@cp -f Resources/question_context.md "$(RESOURCES)/" 2>/dev/null || true
	@xattr -cr "$(APP_BUNDLE)" 2>/dev/null || true
	@codesign --force --sign - --entitlements Autoclaw.entitlements "$(APP_BUNDLE)"
	@echo "Built $(APP_BUNDLE) (debug)"

# Create distributable DMG
DMG_NAME = $(APP_NAME).dmg
DMG_PATH = $(BUILD_DIR)/$(DMG_NAME)
DMG_TMP = $(BUILD_DIR)/dmg-staging

dmg: spm
	@echo "Creating DMG..."
	@rm -rf "$(DMG_TMP)" "$(DMG_PATH)"
	@mkdir -p "$(DMG_TMP)"
	@cp -R "$(APP_BUNDLE)" "$(DMG_TMP)/"
	@ln -s /Applications "$(DMG_TMP)/Applications"
	@hdiutil create -volname "$(APP_NAME)" -srcfolder "$(DMG_TMP)" -ov -format UDZO "$(DMG_PATH)"
	@rm -rf "$(DMG_TMP)"
	@echo ""
	@echo "✅ DMG ready: $(DMG_PATH)"
	@echo "   Share this file — recipients drag Autoclaw.app to Applications."

clean:
	rm -rf $(BUILD_DIR)
	rm -rf .build

run: all
	@-pkill -x "$(APP_NAME)" 2>/dev/null; true
	@sleep 0.3
	@open "$(APP_BUNDLE)"
