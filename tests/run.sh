#!/usr/bin/env sh
set -eu
cd "$(dirname "$0")/.."
lua5.1 tests/test_features.lua
lua5.1 tests/test_architecture.lua
lua5.1 tests/test_pure_modules.lua
lua5.1 tests/test_bug_regressions.lua
lua5.1 tests/test_export_import.lua
lua5.1 tests/test_i18n.lua
lua5.1 tests/test_project_api.lua
lua5.1 tests/test_freeze_first.lua
lua5.1 tests/test_freeze_first_simulation.lua
lua5.1 tests/test_freeze_recovery.lua
lua5.1 tests/test_native_choice_guard.lua
lua5.1 tests/test_load.lua
lua5.1 tests/test_selftests.lua
lua5.1 tests/test_sync_fuzz.lua
