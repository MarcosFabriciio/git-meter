DEVELOPER_DIR ?= /Applications/Xcode.app/Contents/Developer
XCB := DEVELOPER_DIR=$(DEVELOPER_DIR) xcodebuild -project GitMeter.xcodeproj -scheme GitMeter -derivedDataPath build

.PHONY: gen build run test release install dist clean

gen:
	@command -v xcodegen > /dev/null 2>&1 || brew install xcodegen
	xcodegen generate

build: gen
	$(XCB) -configuration Debug build

run: build
	-pkill -x GitMeter
	open build/Build/Products/Debug/GitMeter.app

test: gen
	$(XCB) test

release: gen
	$(XCB) -configuration Release build

install: release
	-pkill -x GitMeter
	rm -rf /Applications/GitMeter.app
	cp -R build/Build/Products/Release/GitMeter.app /Applications/GitMeter.app
	open /Applications/GitMeter.app

dist: release
	$(eval VERSION := $(shell grep 'MARKETING_VERSION:' project.yml | sed 's/.*MARKETING_VERSION: *"\([^"]*\)".*/\1/'))
	mkdir -p dist
	ditto -c -k --keepParent build/Build/Products/Release/GitMeter.app dist/GitMeter-$(VERSION).zip
	shasum -a 256 dist/GitMeter-$(VERSION).zip | tee dist/GitMeter-$(VERSION).zip.sha256

clean:
	rm -rf build dist GitMeter.xcodeproj Support/Info.plist
