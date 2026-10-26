.PHONY: build run install icon vendor clean

build:
	./scripts/build-app.sh

run: build
	open build/ReadEasy.app

install:
	./scripts/build-app.sh --install

icon:
	swift scripts/make-icon.swift Resources/AppIcon.icns

vendor:
	./scripts/vendor.sh

clean:
	rm -rf .build build
