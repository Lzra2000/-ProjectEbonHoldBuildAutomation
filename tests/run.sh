#!/usr/bin/env sh
set -eu
cd "$(dirname "$0")/.."
texlua tests/test_features.lua
texlua tests/test_architecture.lua
texlua tests/test_project_api.lua
texlua tests/test_native_choice_guard.lua
texlua tests/test_load.lua
texlua tests/test_selftests.lua
texlua tests/test_sync_fuzz.lua
