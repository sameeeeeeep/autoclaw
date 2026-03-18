APP_NAME = Autoclaw
BUNDLE_ID = com.autoclaw.app
BUILD_DIR = build
APP_BUNDLE = $(BUILD_DIR)/$(APP_NAME).app
CONTENTS = $(APP_BUNDLE)/Contents
MACOS_DIR = $(CONTENTS)/MacOS
RESOURCES = $(CONTENTS)/Resources

SOURCES = $(wildcard Sources/*.swift)
ARCH = $(shell uname -m)
SDK = $(shell xcrun --show-sdk-path)
TARGET = $(ARCH)-apple-macosx13.0

SWIFT_FLAGS = \
	-parse-as-library \
	-sdk $(SDK) \
	-target $(TARGET)

.PHONY: all clean run

all: $(MACOS_DIR)/$(APP_NAME)

$(MACOS_DIR)/$(APP_NAME): $(SOURCES) Info.plist
	@mkdir -p "$(MACOS_DIR)" "$(RESOURCES)"
	swiftc $(SWIFT_FLAGS) \
		-o "$(MACOS_DIR)/$(APP_NAME)" \
		$(SOURCES)
	@cp Info.plist "$(CONTENTS)/"
	@plutil -replace CFBundleExecutable -string "$(APP_NAME)" "$(CONTENTS)/Info.plist"
	@plutil -replace CFBundleIdentifier -string "$(BUNDLE_ID)" "$(CONTENTS)/Info.plist"
	@if [ -f Resources/AppIcon.icns ]; then cp Resources/AppIcon.icns "$(RESOURCES)/"; fi
	@cp -f Resources/menubar_icon.png Resources/menubar_icon@2x.png Resources/logo_40.png "$(RESOURCES)/" 2>/dev/null || true
	@cp -f Resources/menubar_icon_green.png Resources/menubar_icon_green@2x.png "$(RESOURCES)/" 2>/dev/null || true
	@cp -f Resources/freepik__remove-background__60858.png "$(RESOURCES)/autoclaw_logo.png" 2>/dev/null || true
	@xattr -cr "$(APP_BUNDLE)" 2>/dev/null || true
	@codesign --force --sign - --entitlements Autoclaw.entitlements "$(APP_BUNDLE)"
	@echo "Built $(APP_BUNDLE)"

clean:
	rm -rf $(BUILD_DIR)

run: all
	@-pkill -x "$(APP_NAME)" 2>/dev/null; true
	@sleep 0.3
	@open "$(APP_BUNDLE)"
