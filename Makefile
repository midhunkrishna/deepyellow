# DeepYellow build entry points. Needs only the Swift 6 toolchain on macOS.
#   make test                 run every package test and the release script tests
#   make app                  build dist/DeepYellow.app (universal; ARCHS="arm64" for a quick build)
#   make dmg                  build the app, then dist/DeepYellow.dmg, .zip and SHA256SUMS
#   make install PREFIX=DIR   install the app into DIR/Applications and the CLI link into DIR/.local/bin
#   make check-rules          run the rule checks, the rules doc check and the advisor tests
#   make icon                 regenerate the committed icon files
PREFIX ?= $(HOME)

.PHONY: test check-rules app dmg install icon clean

test:
	scripts/test-all.sh

# Fast check for rule changes: schema check, generated doc up to date, advisor tests.
check-rules:
	python3 scripts/check-rules.py
	python3 scripts/gen-rules-doc.py --check
	swift test --package-path Packages/DYAdvisor

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
