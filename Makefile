.PHONY: test validate shellcheck syntax compile recipes-check recipe-lint recipe-manifest recipe-manifest-check

# Vollständige Test-Suite (bats)
test:
	bats tests/

# Agent/CI-Validierung ohne Wine/Proton
validate: shellcheck syntax compile recipes-check recipe-lint recipe-manifest-check

shellcheck:
	find ./core ./recipes/wiso-steuer ./recipes/photoshop/repair.sh ./launcher ./scripts \
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
	@for f in recipes/*/recipe.yml; do \
		case "$$f" in */_template/*) continue ;; esac; \
		grep -q '^repair:' "$$f" || { echo "missing repair: in $$f"; exit 1; }; \
		grep -q '^validate:' "$$f" || { echo "missing validate: in $$f"; exit 1; }; \
	done

recipe-lint:
	bash ./scripts/recipe-lint.sh

recipe-manifest:
	bash ./scripts/recipe-manifest.sh

recipe-manifest-check: recipe-manifest
	git diff --exit-code recipes/manifest.json
