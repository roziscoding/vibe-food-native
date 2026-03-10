PROJECT := Vibe Food/Vibe Food.xcodeproj
SCHEME := Vibe Food
CONFIGURATION ?= Debug
SIMULATOR_NAME := iPhone 17 Pro
SIMULATOR_RUNTIME := iOS 26.2
SIMULATOR_UDID := 4960D9F5-2D8E-4980-B843-A4BCC70B47CD
BUNDLE_ID := ninja.roz.vibefood
DERIVED_DATA ?= $(CURDIR)/.deriveddata
APP_PATH := $(DERIVED_DATA)/Build/Products/$(CONFIGURATION)-iphonesimulator/Vibe Food.app
SCREENSHOT_DIR ?= /tmp/vibe-food
LOG_PREDICATE := subsystem == "ninja.roz.vibefood"

.PHONY: help build boot install launch run debug rebuild clean screenshot

help:
	@printf '%s\n' \
	  'make build      Build the app for the default simulator' \
	  'make boot       Boot the default simulator and wait until ready' \
	  'make install    Install the current build into the default simulator' \
	  'make launch     Launch the app in the default simulator' \
	  'make run        Boot, install, and launch the app' \
	  'make debug      Build, run, and stream live app logs' \
	  'make rebuild    Build, then boot, install, and launch the app' \
	  'make screenshot Capture a simulator screenshot to $(SCREENSHOT_DIR)' \
	  'make clean      Remove $(DERIVED_DATA)'

build:
	xcodebuild \
	  -project '$(PROJECT)' \
	  -scheme '$(SCHEME)' \
	  -configuration '$(CONFIGURATION)' \
	  -destination 'platform=iOS Simulator,id=$(SIMULATOR_UDID)' \
	  -derivedDataPath '$(DERIVED_DATA)' \
	  build

boot:
	open -a Simulator --args -CurrentDeviceUDID $(SIMULATOR_UDID)
	xcrun simctl boot $(SIMULATOR_UDID) >/dev/null 2>&1 || true
	xcrun simctl bootstatus $(SIMULATOR_UDID) -b

install:
	test -d '$(APP_PATH)' || { echo "Build product not found at $(APP_PATH). Run 'make build' first."; exit 1; }
	xcrun simctl install $(SIMULATOR_UDID) '$(APP_PATH)'

launch:
	xcrun simctl terminate $(SIMULATOR_UDID) $(BUNDLE_ID) >/dev/null 2>&1 || true
	xcrun simctl launch $(SIMULATOR_UDID) $(BUNDLE_ID)

run: boot install launch

debug: build boot install
	@set -e; \
	xcrun simctl terminate $(SIMULATOR_UDID) $(BUNDLE_ID) >/dev/null 2>&1 || true; \
	( sleep 1; xcrun simctl launch --console --terminate-running-process $(SIMULATOR_UDID) $(BUNDLE_ID) >/dev/null ) & \
	printf '%s\n' "Streaming logs for $(BUNDLE_ID). Press Ctrl+C to stop."; \
	xcrun simctl spawn $(SIMULATOR_UDID) log stream --style compact --level info --predicate '$(LOG_PREDICATE)'

rebuild: build run

clean:
	rm -rf '$(DERIVED_DATA)'

screenshot: boot
	mkdir -p '$(SCREENSHOT_DIR)'
	@path='$(SCREENSHOT_DIR)/vibe-food-'$$(date +%Y%m%d-%H%M%S)'.png'; \
	xcrun simctl io $(SIMULATOR_UDID) screenshot "$$path" >/dev/null; \
	printf '%s\n' "$$path"
