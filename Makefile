# Daub — build, test, install.
#
#   make            build the .app into ./build
#   make run        build and launch it
#   make install    build and install into /Applications (override with DESTDIR)
#   make test       run the engine tests
#   make uninstall  remove the installed copy
#   make clean      delete build artefacts

DESTDIR ?= /Applications

.PHONY: all build run install uninstall test clean

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
