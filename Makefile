# Halo — build, package, and tooling.
# Run `make` (or `make help`) to list targets.

APP  := Halo.app
DMG  := Halo.dmg
ICON := Icons/AppIcon.icns

# Code signing / notarization. Leave SIGN_IDENTITY empty for ad-hoc local
# builds; set it for a real release, e.g.:
#   make release SIGN_IDENTITY="Developer ID Application: Amir Raminfar (TEAMID)"
# NOTARY_ARGS picks the notary credentials: a stored keychain profile locally
# (default), or `--key …` flags injected by CI.
SIGN_IDENTITY  ?=
export SIGN_IDENTITY
# App version stamped into Info.plist (CFBundleVersion / ShortVersionString).
# CI sets it from the release tag (v1.2.3 -> 1.2.3); local builds default to
# 0.0.0 so a dev bundle never looks newer than a release to Sparkle.
VERSION        ?=
export VERSION
NOTARY_PROFILE ?= halo-notary
NOTARY_ARGS    ?= --keychain-profile $(NOTARY_PROFILE)

.DEFAULT_GOAL := help
.PHONY: help build test run fmt lint app dmg pack-dmg notarize release notary-creds icon clean

# Everything swift-format touches (rules live in .swift-format).
FMT_PATHS := Sources Tests Plugins Icons Package.swift

help: ## List available targets
	@grep -E '^[a-zA-Z_-]+:.*## ' $(MAKEFILE_LIST) \
		| awk 'BEGIN{FS=":.*## "}{printf "  \033[36m%-7s\033[0m %s\n", $$1, $$2}'

build: ## Build the Halo release binary
	swift build -c release --product Halo

test: ## Run the test suite
	swift test

run: ## Build & launch Halo from source
	swift run Halo

fmt: ## Format all Swift sources in place (swift-format, rules in .swift-format)
	xcrun swift-format -i -r $(FMT_PATHS)

lint: ## Check formatting without modifying files (fails if unformatted)
	xcrun swift-format lint --strict -r $(FMT_PATHS)

app: ## Package Halo.app (release binary + Info.plist + icon, signed per SIGN_IDENTITY)
	swift package --disable-sandbox --allow-writing-to-package-directory bundle-app Halo

dmg: app pack-dmg ## Build a drag-to-install Halo.dmg

# Wrap the *current* Halo.app in a DMG without rebuilding/re-signing it. Used
# both by `dmg` and by `notarize` after the app is stapled — going through the
# `app` target again would re-sign and strip the staple.
pack-dmg:
	@staging="$$(mktemp -d)"; \
	cp -R $(APP) "$$staging/" && \
	ln -s /Applications "$$staging/Applications" && \
	rm -f $(DMG) && \
	hdiutil create -volname Halo -srcfolder "$$staging" -ov -format UDZO $(DMG) >/dev/null; \
	status=$$?; rm -rf "$$staging"; exit $$status
	@echo "✅ Built $(DMG)"

# Notarize BOTH artifacts: staple the .app (what a Homebrew cask copies into
# /Applications — it must be stapled to launch, since the DMG is discarded) AND
# staple the .dmg (for direct downloads). Each has its own hash, so it's two
# submissions: the app first, then the DMG built around the stapled app.
notarize: app ## Notarize & staple Halo.app + Halo.dmg (needs Developer ID + creds)
	@test -n "$(SIGN_IDENTITY)" || { echo "❌ Set SIGN_IDENTITY (see 'make help')"; exit 1; }
	@echo "→ notarizing $(APP)…"
	@tmp="$$(mktemp -d)"; \
	ditto -c -k --keepParent $(APP) "$$tmp/$(APP).zip" && \
	xcrun notarytool submit "$$tmp/$(APP).zip" $(NOTARY_ARGS) --wait; \
	status=$$?; rm -rf "$$tmp"; exit $$status
	xcrun stapler staple $(APP)
	@$(MAKE) --no-print-directory pack-dmg
	@echo "→ notarizing $(DMG)…"
	xcrun notarytool submit $(DMG) $(NOTARY_ARGS) --wait
	xcrun stapler staple $(DMG)
	@echo "── verification ──"
	xcrun stapler validate $(APP)
	xcrun stapler validate $(DMG)
	spctl -a -t exec -vv $(APP)
	@echo "✅ Notarized & stapled $(APP) and $(DMG)"

release: notarize ## Full signed + notarized release DMG (set SIGN_IDENTITY)
	@echo "✅ Release ready: $(DMG)"

notary-creds: ## Store an App Store Connect API key as the local notary profile (interactive)
	xcrun notarytool store-credentials "$(NOTARY_PROFILE)"

icon: $(ICON) ## Regenerate the app icon (.icns) from Icons/make-icon.swift

$(ICON): Icons/make-icon.swift
	@work="$$(mktemp -d)"; \
	swift Icons/make-icon.swift "$$work/icon_1024.png" 1024; \
	set="$$work/AppIcon.iconset"; mkdir -p "$$set"; \
	for s in 16 32 128 256 512; do \
		sips -z $$s $$s "$$work/icon_1024.png" --out "$$set/icon_$${s}x$${s}.png" >/dev/null; \
		d=$$((s * 2)); \
		sips -z $$d $$d "$$work/icon_1024.png" --out "$$set/icon_$${s}x$${s}@2x.png" >/dev/null; \
	done; \
	iconutil -c icns "$$set" -o $(ICON); \
	rm -rf "$$work"; \
	echo "✅ Built $(ICON)"

clean: ## Remove build artifacts (Halo.app, Halo.dmg, .build)
	rm -rf $(APP) $(DMG)
	swift package clean
