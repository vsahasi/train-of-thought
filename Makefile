APP = build/Train of Thought.app

.PHONY: all app universal run test install clean hero probe

all: app

## Build the .app bundle (works with just the Command Line Tools)
app:
	@Scripts/bundle.sh

## Build a universal (arm64 + x86_64) bundle
universal:
	@ARCHS="arm64 x86_64" Scripts/bundle.sh

## Build and launch
run: app
	@open "$(APP)"

## Run the TrainCore tests: XCTest with Xcode, the stand-in without
test:
	@if xcrun --show-sdk-platform-path >/dev/null 2>&1; then swift test; else Scripts/test-clt.sh; fi

## Copy the bundle into /Applications
install: app
	@rm -rf "/Applications/Train of Thought.app"
	@cp -R "$(APP)" /Applications/
	@echo "installed to /Applications/Train of Thought.app"

clean:
	@rm -rf .build build

## Regenerate the README hero (assets/hero.svg) from the sprites
hero: app
	@swiftc -sdk $$(xcrun --show-sdk-path) -target $$(uname -m)-apple-macos13 -O -I .build/bundle/$$(uname -m) -L .build/bundle/$$(uname -m) -lTrainCore \
	  Sources/TrainOfThought/Overlay/Pixel.swift Sources/TrainOfThought/Overlay/Sprites.swift Scripts/make-hero/main.swift -o .build/bundle/make-hero
	@.build/bundle/make-hero assets/hero.svg

## Watch the notification-banner sensor
probe: app
	@"$(APP)/Contents/MacOS/TrainOfThought" --probe
