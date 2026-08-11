"""Vulture whitelist: symbols kept for tests / intentional Fluent facade.

Fluent names are the ui_fluent public surface for callers / future UI.
manifest_needs_sync is exercised from tests/test_recipe_trust.bats (outside
the launcher/ scan path).
"""

# unused import (launcher/ui_fluent.py)
BodyLabel
CaptionLabel
FluentIcon
Pivot
StrongBodyLabel
SubtitleLabel
MenuAnimationType

# unused function (launcher/recipe_trust.py) — bats imports it
manifest_needs_sync
