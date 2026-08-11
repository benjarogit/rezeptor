.PHONY: test pytest validate shellcheck syntax compile i18n-check ruff dead-code shell-dup-check recipes-check recipe-lint recipe-manifest recipe-manifest-check

# Shell test suite (bats). Python unit tests: make pytest (CI runs both).
test:
	bats tests/

# Launcher Python unit tests under tests/*.py (needs: pip install pytest PyQt6).
pytest:
	QT_QPA_PLATFORM=offscreen python3 -m pytest tests/ -q

# Agent/CI-Validierung ohne Wine/Proton (local; CI also runs make test + make pytest).
validate: shellcheck syntax compile i18n-check ruff recipes-check recipe-lint recipe-manifest-check

shellcheck:
	find ./core ./recipes/wiso-steuer ./recipes/photoshop ./recipes/premiere ./launcher ./scripts \
		-name '*.sh' -print0 \
		| xargs -0 shellcheck -S error -e SC1091,SC2034,SC2155,SC2207

syntax:
	@for f in core/*.sh recipes/*/*.sh launcher/*.sh scripts/*.sh; do \
		[ -f "$$f" ] || continue; \
		bash -n "$$f" || exit 1; \
	done

compile:
	python3 -m compileall -q launcher/

i18n-check:
	python3 scripts/check-i18n-parity.py

ruff:
	@if command -v ruff >/dev/null 2>&1; then \
		ruff check launcher; \
	elif python3 -m ruff --version >/dev/null 2>&1; then \
		python3 -m ruff check launcher; \
	else \
		echo "ruff missing — install: pacman -S ruff  OR  pipx install ruff  OR  see requirements-dev.txt" >&2; \
		exit 1; \
	fi

# Opt-in: unreachable Python in launcher/ (see pyproject.toml [tool.vulture]).
# Not in validate — Qt/Fluent false positives need curated whitelist.
dead-code:
	@if command -v vulture >/dev/null 2>&1; then \
		vulture; \
	elif python3 -m vulture --version >/dev/null 2>&1; then \
		python3 -m vulture; \
	else \
		echo "vulture missing — install: pacman -S vulture  OR  pip install -r requirements-dev.txt (venv)" >&2; \
		exit 1; \
	fi

# Opt-in: recipe hook scripts must not redefine core/ function names.
# Not in validate — rare intentional overlaps go in scripts/shell-dup-allowlist.txt.
shell-dup-check:
	python3 scripts/check-shell-dup-funcs.py

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
