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
KCAL ?= 0
PROTEIN ?= 0
CARBS ?= 0
FAT ?= 0
PORTION ?= 1
UNIT ?= g

.PHONY: help build boot install launch run debug rebuild clean screenshot command command-tab command-day command-water command-meal command-ingredient

help:
	@printf '%s\n' \
	  'make build      Build the app for the default simulator' \
	  'make boot       Boot the default simulator and wait until ready' \
	  'make install    Install the current build into the default simulator' \
	  'make launch     Launch the app in the default simulator' \
	  'make run        Boot, install, and launch the app' \
	  'make debug      Build, run, and stream live app logs' \
	  'make rebuild    Build, then boot, install, and launch the app' \
	  'make command    Send a command without URL confirmation (relaunches app)' \
	  'make command-tab TAB=<name>      Switch app tab (dashboard|food|input|water|settings)' \
	  'make command-day DAY=<value>     Change selected day (today|previous|next|YYYY-MM-DD)' \
	  'make command-water ML=<amount> [DATE=YYYY-MM-DD]   Log water entry in ml' \
	  'make command-meal NAME=<name> [KCAL=.. PROTEIN=.. CARBS=.. FAT=.. DATE=YYYY-MM-DD]' \
	  'make command-ingredient NAME=<name> [UNIT=g PORTION=1 KCAL=.. PROTEIN=.. CARBS=.. FAT=..]' \
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

command: boot
	@test -n "$(URL)" || { echo "Usage: make command URL='vibefood://command/tab?name=water'"; exit 1; }
	SIMCTL_CHILD_VF_URL_COMMAND="$(URL)" \
	xcrun simctl launch --terminate-running-process $(SIMULATOR_UDID) $(BUNDLE_ID)

command-tab:
	@test -n "$(TAB)" || { echo "Usage: make command-tab TAB=water"; exit 1; }
	@$(MAKE) command URL="vibefood://command/tab?name=$(TAB)"

command-day:
	@test -n "$(DAY)" || { echo "Usage: make command-day DAY=today"; exit 1; }
	@$(MAKE) command URL="vibefood://command/day?value=$(DAY)"

command-water:
	@test -n "$(ML)" || { echo "Usage: make command-water ML=350 [DATE=YYYY-MM-DD]"; exit 1; }
	@url="vibefood://command/water/add?ml=$(ML)"; \
	if [ -n "$(DATE)" ]; then url="$$url&date=$(DATE)"; fi; \
	$(MAKE) command URL="$$url"

command-meal:
	@test -n "$(NAME)" || { echo "Usage: make command-meal NAME='Chicken Rice' [KCAL=600 PROTEIN=40 CARBS=70 FAT=15 DATE=YYYY-MM-DD]"; exit 1; }
	@name=$$(printf '%s' "$(NAME)" | sed 's/ /%20/g'); \
	url="vibefood://command/meal/add?name=$$name&kcal=$(KCAL)&protein=$(PROTEIN)&carbs=$(CARBS)&fat=$(FAT)"; \
	if [ -n "$(DATE)" ]; then url="$$url&date=$(DATE)"; fi; \
	$(MAKE) command URL="$$url"

command-ingredient:
	@test -n "$(NAME)" || { echo "Usage: make command-ingredient NAME='Oats' [UNIT=g PORTION=100 KCAL=389 PROTEIN=17 CARBS=66 FAT=7]"; exit 1; }
	@name=$$(printf '%s' "$(NAME)" | sed 's/ /%20/g'); \
	unit=$$(printf '%s' "$(UNIT)" | sed 's/ /%20/g'); \
	url="vibefood://command/ingredient/add?name=$$name&unit=$$unit&portion=$(PORTION)&kcal=$(KCAL)&protein=$(PROTEIN)&carbs=$(CARBS)&fat=$(FAT)"; \
	$(MAKE) command URL="$$url"
