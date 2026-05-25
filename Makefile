APP_NAME   = API音声ソフト
APP_BUNDLE = build/$(APP_NAME).app
EXECUTABLE = $(APP_BUNDLE)/Contents/MacOS/APIVoiceInputApp
SIGN_ID    = Whispur Compact Local Code Signing

.PHONY: build sign restart

build:
	swift build -c release 2>&1

sign: build
	cp .build/arm64-apple-macosx/release/APIVoiceInputApp "$(EXECUTABLE)"
	cp Info.plist "$(APP_BUNDLE)/Contents/Info.plist"
	codesign --sign "$(SIGN_ID)" --force --deep "$(APP_BUNDLE)"

restart: sign
	pkill -f APIVoiceInputApp 2>/dev/null || true
	sleep 1
	open "$(APP_BUNDLE)"
	@echo "起動しました"
