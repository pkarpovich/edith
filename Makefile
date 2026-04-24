SCHEME = edith
DESTINATION = platform=macOS,arch=arm64
SIGN_OVERRIDES = CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM=

.PHONY: all generate build test clean

all: build test

generate:
	xcodegen generate

build:
	xcodebuild -scheme $(SCHEME) -destination '$(DESTINATION)' $(SIGN_OVERRIDES) build

test:
	xcodebuild -scheme $(SCHEME) -destination '$(DESTINATION)' $(SIGN_OVERRIDES) test

clean:
	xcodebuild -scheme $(SCHEME) clean
	rm -rf build DerivedData
