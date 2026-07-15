.PHONY: test validate shellcheck syntax compile recipes-check recipe-lint recipe-manifest recipe-manifest-check

# Vollständige Test-Suite (bats)
test:
	bats tests/

# Agent/CI-Validierung ohne Wine/Proton
validate: shellcheck syntax compile recipes-check recipe-lint recipe-manifest-check

shellcheck:
	find ./core ./recipes/wiso-steuer ./recipes/photoshop ./launcher ./scripts \
		-name '*.sh' -print0 \
		| xargs -0 shellcheck -S error -e SC1091,SC2034,SC2155,SC2207

syntax:
	@for f in core/*.sh recipes/*/*.sh launcher/*.sh scripts/*.sh; do \
		[ -f "$$f" ] || continue; \
		bash -n "$$f" || exit 1; \
	done

compile:
	python3 -m compileall -q launcher/

recipes-check:
	@for f in recipes/*/recipe.yml recipes/community/*/recipe.yml; do \
		[ -f "$$f" ] || continue; \
		case "$$f" in */_*) continue ;; esac; \
		grep -q '^repair:' "$$f" || { echo "missing repair: in $$f"; exit 1; }; \
		grep -q '^validate:' "$$f" || { echo "missing validate: in $$f"; exit 1; }; \
		grep -q '^uninstall:' "$$f" || { echo "missing uninstall: in $$f"; exit 1; }; \
		u=$$(grep -E '^uninstall:' "$$f" | head -1 | sed 's/^uninstall:[[:space:]]*//;s/[\"'\'']//g'); \
		d=$$(dirname "$$f"); \
		[ -f "$$d/$$u" ] || { echo "missing uninstall file $$d/$$u"; exit 1; }; \
		grep -q 'recipe_hooks::purge_recipe_data' "$$d/$$u" \
			|| { echo "$$d/$$u must call recipe_hooks::purge_recipe_data"; exit 1; }; \
	done

recipe-lint:
	bash ./scripts/recipe-lint.sh

recipe-manifest:
	bash ./scripts/recipe-manifest.sh

recipe-manifest-check: recipe-manifest
	git diff --exit-code recipes/manifest.json
