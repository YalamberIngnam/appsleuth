.PHONY: build release test install uninstall clean

build:
	swift build

release:
	swift build -c release

test:
	swift test

install:
	./scripts/install.sh

uninstall:
	./scripts/uninstall.sh

clean:
	swift package clean
