#  PUBLICNODE VPS BUILD ORCHESTRATOR
# (c) 2026 mohammadhasanulislam
# Industry-Grade Automated Build System
#
# SYNC PIPELINE (runs on every build):
#   1. master_build_vps.py → regenerates vps_setup.ipynb from config
#   2. update_and_embed.py → encodes vps-os/*.py + embeds into notebook_template.dart
#   This guarantees notebook_template.dart always reflects the latest config + engine.

.PHONY: sync build-apk build-linux release audit clean help

help:
	@echo "PublicNode App Build Orchestrator"
	@echo "Usage: make [target]"
	@echo ""
	@echo "Targets:"
	@echo "  sync           Full pipeline: rebuild notebook + encode engines + embed into Dart"
	@echo "  audit          Run full codebase audit (auto-syncs first)"
	@echo "  build-apk      Build Android APK (Release)"
	@echo "  build-linux    Package Linux (DEB & RPM)"
	@echo "  release        Build ALL formats + publish to GitHub Releases"
	@echo "  clean          Purge build artifacts"

sync:
	uv run vps-dist-sync

audit: sync
	uv run vps-dev-audit

build-apk: sync
	uv run vps-dist apk

build-linux: sync
	uv run vps-dist linux

release: sync
	uv run vps-release

clean:
	./vps-cli.sh clean
	cd vps-app && flutter clean
