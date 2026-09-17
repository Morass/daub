# Daub — build, test, install.
#
#   make            build the .app into ./build
#   make run        build and launch it
#   make install    build and install into /Applications (override with DESTDIR)
#   make test       run the engine tests
#   make uninstall  remove the installed copy
#   make clean      delete build artefacts

DESTDIR ?= /Applications

.PHONY: all build run install uninstall test clean readme-art

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

clean:
	rm -rf .build build

## Re-render the picture at the top of the README, using the app's own engine.
readme-art:
	swift build
	swiftc -O -I .build/debug/Modules Scripts/make-readme-art.swift \
		.build/debug/DaubCore.build/*.o -o .build/make-readme-art
	.build/make-readme-art Resources/readme-art.png
