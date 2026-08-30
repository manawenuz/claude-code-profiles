#!/usr/bin/env fish

# Dependency-free Fish smoke tests for both profile adapters.

set -l script_dir (path dirname (status filename))
set -g test_root (mktemp -d /tmp/fish-profile-test.XXXXXX)
set -g home_dir "$test_root/home"
set -g data_dir "$test_root/data"
set -g bin_dir "$test_root/bin"
set -g gui_source "$test_root/gui-source"
set -g pass_count 0
set -g fail_count 0

mkdir -p "$home_dir/.gemini/antigravity-cli" "$gui_source/User" "$bin_dir"
set -gx HOME $home_dir
set -gx XDG_DATA_HOME $data_dir
set -gx AGENT_PROFILE_DATA_DIR "$data_dir/agent-profiles"
set -gx PATH $bin_dir $PATH
set -gx AGENT_PROFILE_ANTIGRAVITY_GUI_DATA_DIR $gui_source
set -gx CLAUDE_PROFILE_NO_UPDATE_CHECK 1
set -gx CLAUDE_PROFILE_AUTO_QUIET 1

# Keep inherited session state from affecting the assertions.
for variable_name in CLAUDE_CONFIG_DIR CLAUDE_PROFILE_AUTO_SET AGENT_PROFILE_ANTIGRAVITY_ACTIVE AGENT_PROFILE_CODEX_ACTIVE __claude_profile_auto_off __claude_profile_auto_last_pwd
    set -e $variable_name 2>/dev/null
end

# Do not let an older globally installed adapter mask the files under test.
for function_name in agent-profile antigravity antigravity-ide agy codex agy-profile antigravity-profile codex-profile claude claude-profile
    functions -e $function_name 2>/dev/null
end

source "$script_dir/../agent-profile.fish"
source "$script_dir/../claude-profile.fish"

if not functions -q agent-profile; or not functions -q claude-profile
    printf 'required Fish profile functions are not defined\n' >&2
    rm -rf "$test_root"
    exit 1
end

function assert_file_contains
    set -l file $argv[1]
    set -l expected $argv[2]
    grep -Fqx -- "$expected" "$file"
end

function pass_test
    set -g pass_count (math $pass_count + 1)
    printf 'ok - %s\n' $argv[1]
end

function fail_test
    set -g fail_count (math $fail_count + 1)
    printf 'not ok - %s\n' $argv[1]
end

function run_test
    set -l name $argv[1]
    $name
    if test $status -eq 0
        pass_test $name
    else
        fail_test $name
    end
end

function test_agent_live_copy_and_wrappers
    printf '%s' oauth-token > "$HOME/.gemini/antigravity-cli/token"
    printf '%s' gui-settings > "$gui_source/User/settings.json"
    agent-profile copy antigravity hafez >/dev/null
    or return 1
    test -f "$AGENT_PROFILE_DATA_DIR/antigravity/hafez/home/.gemini/antigravity-cli/token"
    or return 1
    printf '%s\n' '#!/bin/sh' 'env | grep "^HOME=" > "$AGENT_PROFILE_TEST_LOG"' > "$bin_dir/agy"
    chmod +x "$bin_dir/agy"
    set -gx AGENT_PROFILE_TEST_LOG "$test_root/agy.log"
    agent-profile default antigravity hafez >/dev/null
    agy >/dev/null
    assert_file_contains "$AGENT_PROFILE_TEST_LOG" "HOME=$AGENT_PROFILE_DATA_DIR/antigravity/hafez/home"
end

function test_agent_gui_restart
    printf '%s\n' '#!/bin/sh' 'printf "GUI_ARGS=%s\\n" "$*" > "$AGENT_PROFILE_TEST_LOG"' > "$bin_dir/antigravity"
    chmod +x "$bin_dir/antigravity"
    set -e AGENT_PROFILE_ANTIGRAVITY_GUI_COMMAND
    agent-profile restart antigravity >/dev/null
    or return 1
    assert_file_contains "$AGENT_PROFILE_TEST_LOG" "GUI_ARGS=--user-data-dir $AGENT_PROFILE_DATA_DIR/antigravity/hafez/gui-user-data --new-window"
end

function test_codex_live_copy_and_wrapper
    mkdir -p "$HOME/.codex"
    printf '%s' codex-token > "$HOME/.codex/auth.json"
    agent-profile copy codex codexwork >/dev/null
    or return 1
    test -f "$AGENT_PROFILE_DATA_DIR/codex/codexwork/auth.json"
    or return 1
    printf '%s\n' '#!/bin/sh' 'env | grep "^CODEX_HOME=" > "$AGENT_PROFILE_TEST_LOG"' > "$bin_dir/codex"
    chmod +x "$bin_dir/codex"
    set -gx AGENT_PROFILE_TEST_LOG "$test_root/codex.log"
    agent-profile default codex codexwork >/dev/null
    codex >/dev/null
    assert_file_contains "$AGENT_PROFILE_TEST_LOG" "CODEX_HOME=$AGENT_PROFILE_DATA_DIR/codex/codexwork"
end

function test_claude_wrapper
    claude-profile create work >/dev/null
    or return 1
    claude-profile default work >/dev/null
    or return 1
    printf '%s\n' '#!/bin/sh' 'env | grep "^CLAUDE_CONFIG_DIR=" > "$CLAUDE_PROFILE_TEST_LOG"' > "$bin_dir/claude"
    chmod +x "$bin_dir/claude"
    set -gx CLAUDE_PROFILE_TEST_LOG "$test_root/claude.log"
    claude >/dev/null
    assert_file_contains "$CLAUDE_PROFILE_TEST_LOG" "CLAUDE_CONFIG_DIR=$XDG_DATA_HOME/claude-profiles/work"
end

function test_claude_create_init_and_status
    claude-profile create --init initialized >/dev/null
    or return 1
    test -s "$XDG_DATA_HOME/claude-profiles/initialized/settings.json"
    or return 1
    claude-profile list | grep -Fq initialized
    or return 1
    claude-profile version | grep -Fqx 1.3.0
end

function test_claude_directory_local_switching
    set -l project_dir "$test_root/project"
    mkdir -p "$project_dir"
    cd "$project_dir"
    claude-profile local work >/dev/null
    or return 1
    set -e CLAUDE_CONFIG_DIR
    set -e CLAUDE_PROFILE_AUTO_SET
    claude-profile auto on >/dev/null
    or return 1
    test "$CLAUDE_CONFIG_DIR" = "$XDG_DATA_HOME/claude-profiles/work"
    or return 1
    claude-profile auto status | grep -Fq 'Auto-switching: enabled'
    or return 1
    cd "$test_root"
    not set -q CLAUDE_CONFIG_DIR
end

function test_claude_skill_pool_backend
    set -l skill_dir "$test_root/skill-source"
    mkdir -p "$skill_dir"
    printf '%s\n' '# demo skill' > "$skill_dir/SKILL.md"
    claude-profile skills register demo "$skill_dir" >/dev/null
    or return 1
    test -L "$XDG_DATA_HOME/claude-profiles/skills/demo"
    or return 1
    claude-profile skills add demo work >/dev/null
    or return 1
    test -L "$XDG_DATA_HOME/claude-profiles/work/skills/demo"
    or return 1
end

function test_fish_validation_and_no_overwrite
    if agent-profile create antigravity bad/name >/dev/null 2>&1
        return 1
    end
    if claude-profile create .hidden >/dev/null 2>&1
        return 1
    end
    printf '%s' keep > "$AGENT_PROFILE_DATA_DIR/codex/codexwork/auth.json"
    if agent-profile copy codex codexwork >/dev/null 2>&1
        return 1
    end
    assert_file_contains "$AGENT_PROFILE_DATA_DIR/codex/codexwork/auth.json" keep
end

run_test test_agent_live_copy_and_wrappers
run_test test_agent_gui_restart
run_test test_codex_live_copy_and_wrapper
run_test test_claude_wrapper
run_test test_claude_create_init_and_status
run_test test_claude_directory_local_switching
run_test test_claude_skill_pool_backend
run_test test_fish_validation_and_no_overwrite

printf '\n%d passed, %d failed\n' $pass_count $fail_count
rm -rf "$test_root"
test $fail_count -eq 0
