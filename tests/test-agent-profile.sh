#!/usr/bin/env bash

# Dependency-free behavior tests for agent-profile.sh.

set -u

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/agent-profile-test.XXXXXX") || exit 1
trap 'rm -rf "$TEST_ROOT"' EXIT HUP INT TERM

HOME="$TEST_ROOT/home"
XDG_DATA_HOME="$TEST_ROOT/data"
PATH="$TEST_ROOT/bin:$PATH"
export HOME XDG_DATA_HOME PATH
ORIGINAL_CODEX_HOME=${CODEX_HOME-}

mkdir -p "$HOME" "$TEST_ROOT/bin"

# The implementation is intentionally sourced after the test environment is
# prepared, just like a user's shell profile.
if [ -f "$SCRIPT_DIR/../agent-profile.sh" ]; then
    # shellcheck disable=SC1091
    . "$SCRIPT_DIR/../agent-profile.sh"
fi

if ! command -v agent-profile >/dev/null 2>&1; then
    printf 'not ok - agent-profile command is defined\n'
    exit 1
fi

PASS=0
FAIL=0

fail() {
    printf 'not ok - %s\n' "$1"
    FAIL=$((FAIL + 1))
}

pass() {
    printf 'ok - %s\n' "$1"
    PASS=$((PASS + 1))
}

assert_file() {
    _assert_file_path=$1
    _assert_file_expected=$2
    if [ -f "$_assert_file_path" ] && [ "$(cat "$_assert_file_path")" = "$_assert_file_expected" ]; then
        return 0
    fi
    printf 'expected %s to contain %s\n' "$_assert_file_path" "$_assert_file_expected" >&2
    return 1
}

assert_contains() {
    _assert_contains_file=$1
    _assert_contains_text=$2
    grep -F -- "$_assert_contains_text" "$_assert_contains_file" >/dev/null 2>&1
}

test_invalid_name_rejected() {
    if agent-profile create antigravity '../escape' >/dev/null 2>&1; then
        return 1
    fi
    [ ! -e "$XDG_DATA_HOME/agent-profiles/antigravity/../escape" ]
}

test_copy_live_antigravity() {
    mkdir -p "$HOME/.gemini/antigravity-cli" "$TEST_ROOT/gui-source/User"
    printf 'oauth-token' > "$HOME/.gemini/antigravity-cli/antigravity-oauth-token"
    printf 'gui-settings' > "$TEST_ROOT/gui-source/User/settings.json"
    AGENT_PROFILE_ANTIGRAVITY_GUI_DATA_DIR="$TEST_ROOT/gui-source"
    export AGENT_PROFILE_ANTIGRAVITY_GUI_DATA_DIR

    agent-profile copy antigravity hafez >/dev/null 2>&1 || return 1
    assert_file "$XDG_DATA_HOME/agent-profiles/antigravity/hafez/home/.gemini/antigravity-cli/antigravity-oauth-token" 'oauth-token' || return 1
    assert_file "$XDG_DATA_HOME/agent-profiles/antigravity/hafez/gui-user-data/User/settings.json" 'gui-settings'
}

test_copy_from_default_and_no_overwrite() {
    agent-profile create antigravity work >/dev/null 2>&1 || return 1
    printf 'work-marker' > "$XDG_DATA_HOME/agent-profiles/antigravity/work/marker"
    agent-profile default antigravity work >/dev/null 2>&1 || return 1
    agent-profile copy antigravity default copied >/dev/null 2>&1 || return 1
    assert_file "$XDG_DATA_HOME/agent-profiles/antigravity/copied/marker" 'work-marker' || return 1

    printf 'keep-marker' > "$XDG_DATA_HOME/agent-profiles/antigravity/copied/marker"
    if agent-profile copy antigravity work copied >/dev/null 2>&1; then
        return 1
    fi
    assert_file "$XDG_DATA_HOME/agent-profiles/antigravity/copied/marker" 'keep-marker' || return 1
    agent-profile copy antigravity work copied --force >/dev/null 2>&1 || return 1
    assert_file "$XDG_DATA_HOME/agent-profiles/antigravity/copied/marker" 'work-marker'
}

test_agy_wrapper_isolates_home() {
    printf '#!/bin/sh\nenv | grep "^HOME=" > "$AGENT_PROFILE_TEST_LOG"\n' > "$TEST_ROOT/bin/agy"
    chmod +x "$TEST_ROOT/bin/agy"
    AGENT_PROFILE_TEST_LOG="$TEST_ROOT/agy.log"
    export AGENT_PROFILE_TEST_LOG

    agent-profile use antigravity copied >/dev/null 2>&1 || return 1
    agy --print >/dev/null 2>&1 || return 1
    assert_file "$AGENT_PROFILE_TEST_LOG" "HOME=$XDG_DATA_HOME/agent-profiles/antigravity/copied/home" || return 1
    [ "$HOME" = "$TEST_ROOT/home" ]
}

test_codex_wrapper_sets_codex_home() {
    mkdir -p "$HOME/.codex"
    printf 'model = "gpt-test"\n' > "$HOME/.codex/config.toml"
    agent-profile copy codex hafez >/dev/null 2>&1 || return 1
    agent-profile default codex hafez >/dev/null 2>&1 || return 1
    printf '#!/bin/sh\nenv | grep "^CODEX_HOME=" > "$AGENT_PROFILE_TEST_LOG"\n' > "$TEST_ROOT/bin/codex"
    chmod +x "$TEST_ROOT/bin/codex"
    codex >/dev/null 2>&1 || return 1
    assert_file "$AGENT_PROFILE_TEST_LOG" "CODEX_HOME=$XDG_DATA_HOME/agent-profiles/codex/hafez" || return 1
    [ "${CODEX_HOME-}" = "$ORIGINAL_CODEX_HOME" ]
}

test_gui_wrapper_injects_user_data_dir() {
    printf '#!/bin/sh\nprintf "GUI_ARGS=%%s\\n" "$*" > "$AGENT_PROFILE_TEST_LOG"\n' > "$TEST_ROOT/bin/antigravity"
    chmod +x "$TEST_ROOT/bin/antigravity"
    AGENT_PROFILE_ANTIGRAVITY_GUI_COMMAND=antigravity
    export AGENT_PROFILE_ANTIGRAVITY_GUI_COMMAND
    antigravity --new-window >/dev/null 2>&1 || return 1
    assert_contains "$AGENT_PROFILE_TEST_LOG" "--user-data-dir $XDG_DATA_HOME/agent-profiles/antigravity/copied/gui-user-data" || return 1

    antigravity --user-data-dir /tmp/custom-gui >/dev/null 2>&1 || return 1
    assert_contains "$AGENT_PROFILE_TEST_LOG" 'GUI_ARGS=--user-data-dir /tmp/custom-gui'
}

run_test() {
    _test_name=$1
    if "$@"; then
        pass "$_test_name"
    else
        fail "$_test_name"
    fi
}

run_test test_invalid_name_rejected
run_test test_copy_live_antigravity
run_test test_copy_from_default_and_no_overwrite
run_test test_agy_wrapper_isolates_home
run_test test_codex_wrapper_sets_codex_home
run_test test_gui_wrapper_injects_user_data_dir

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
