VERSION ?= 0.1.0
APP := dist/AIUsageMonitor.app

.PHONY: build test probe app install run clean

build:
	swift build

test:
	swift test

# One snapshot printed to stdout: the probes, without the menu bar.
probe:
	swift run AIUsageMonitor --probe

app:
	VERSION=$(VERSION) ./scripts/bundle.sh

install: app
	rm -rf /Applications/AIUsageMonitor.app
	cp -R $(APP) /Applications/AIUsageMonitor.app
	open /Applications/AIUsageMonitor.app

run: app
	open $(APP)

clean:
	rm -rf .build dist
