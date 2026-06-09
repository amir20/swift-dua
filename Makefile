# Halo — build, package, and tooling.
# Run `make` (or `make help`) to list targets.

APP  := Halo.app
DMG  := Halo.dmg
ICON := Icons/AppIcon.icns

.DEFAULT_GOAL := help
.PHONY: help build test run app dmg icon clean

help: ## List available targets
	@grep -E '^[a-zA-Z_-]+:.*## ' $(MAKEFILE_LIST) \
		| awk 'BEGIN{FS=":.*## "}{printf "  \033[36m%-7s\033[0m %s\n", $$1, $$2}'

build: ## Compile everything (debug)
	swift build

test: ## Run the test suite
	swift test

run: ## Build & launch Halo from source
	swift run Halo

app: ## Package Halo.app (release binary + Info.plist + icon + ad-hoc sign)
	swift package --disable-sandbox --allow-writing-to-package-directory bundle-app Halo

dmg: app ## Build a drag-to-install Halo.dmg
	@staging="$$(mktemp -d)"; \
	cp -R $(APP) "$$staging/"; \
	ln -s /Applications "$$staging/Applications"; \
	rm -f $(DMG); \
	hdiutil create -volname Halo -srcfolder "$$staging" -ov -format UDZO $(DMG) >/dev/null; \
	rm -rf "$$staging"; \
	echo "✅ Built $(DMG)"

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
