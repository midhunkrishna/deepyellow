# DeepYellow build entry points. Needs only the Swift 6 toolchain on macOS.
#   make test                 run every package test and the release script tests
#   make app                  build dist/DeepYellow.app (universal; ARCHS="arm64" for a quick build)
#   make dmg                  build the app, then dist/DeepYellow.dmg, .zip and SHA256SUMS
#   make install PREFIX=DIR   install the app into DIR/Applications and the CLI link into DIR/.local/bin
#   make icon                 regenerate the committed icon files
PREFIX ?= $(HOME)

.PHONY: test app dmg install icon clean

test:
	scripts/test-all.sh

app:
	scripts/build-app.sh

dmg: app
	scripts/package.sh

install: dmg
	scripts/install.sh --from-file dist/DeepYellow.zip --dir "$(PREFIX)/Applications" --bin "$(PREFIX)/.local/bin"

icon:
	scripts/make-icon.sh

clean:
	rm -rf dist
