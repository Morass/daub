# Daub — build, test, install.
#
#   make            build the .app into ./build
#   make run        build and launch it
#   make install    build and install into /Applications (override with DESTDIR)
#   make test       run the engine tests
#   make selftest   drive the real app through the clipboard paths (needs a GUI session)
#   make uninstall  remove the installed copy
#   make clean      delete build artefacts

DESTDIR ?= /Applications

.PHONY: all build run install uninstall test selftest clean readme-art screenshot

all: build

build:
	./Scripts/build-app.sh release

run: build
	open build/Daub.app

install:
	DAUB_INSTALL_DIR="$(DESTDIR)" ./Scripts/install.sh

uninstall:
	rm -rf "$(DESTDIR)/Daub.app" "$(HOME)/Applications/Daub.app"
	@echo "removed Daub.app"

test:
	swift test

## End-to-end clipboard checks against the real app: paste, canvas growth, undo, import.
## Needs a logged-in GUI session, and it does overwrite the clipboard while it runs.
selftest: build
	DAUB_SELFTEST=clipboard build/Daub.app/Contents/MacOS/Daub

clean:
	rm -rf .build build

## Re-render the picture at the top of the README, using the app's own engine.
readme-art:
	swift build
	swiftc -O -I .build/debug/Modules Scripts/make-readme-art.swift \
		.build/debug/DaubCore.build/*.o -o .build/make-readme-art
	.build/make-readme-art Resources/readme-art.png

## Re-take the screenshot at the top of the README. The app renders its own window into a
## PNG — no screen recording, no permission prompt — so this works over SSH, but it does
## need a logged-in GUI session on the machine that runs it.
screenshot: build
	DAUB_SCREENSHOT="$(PWD)/Resources/readme-screenshot.png" \
	DAUB_SCREENSHOT_ART="$(PWD)/Resources/readme-art.png" \
		build/Daub.app/Contents/MacOS/Daub
