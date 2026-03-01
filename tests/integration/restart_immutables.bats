#!/usr/bin/env bats
load '../test_helper/integration'

_name_file() { echo "${BATS_FILE_TMPDIR}/restart_immut_name"; }
_fixture_dir_file() { echo "${BATS_FILE_TMPDIR}/restart_immut_fixture_dir"; }

setup_file() {
  local fixture_dir
  fixture_dir="$(cd "$(dirname "${BATS_TEST_FILENAME}")/../fixtures" && pwd)"
  echo "$fixture_dir" > "$(_fixture_dir_file)"

  local name="test-${BATS_ROOT_PID:-$$}-immut"
  echo "$name" > "$(_name_file)"

  # Create container with domain filtering, then stop it
  "${PROJECT_ROOT}/bin/sandbox-start" "$name" --stack base \
    --domains-file "${fixture_dir}/test-allowlist.txt" \
    --cpu 2 --memory 512MB

  "${PROJECT_ROOT}/bin/sandbox-stop" "$name"
}

teardown_file() {
  local name
  name=$(<"$(_name_file)")
  "${PROJECT_ROOT}/bin/sandbox-stop" "$name" --rm 2>/dev/null || true
}

setup() {
  TEST_TMPDIR="$(mktemp -d)"
  TEST_CONTAINER_NAME=$(<"$(_name_file)")
}

# ── Immutable flag rejection tests (container is stopped) ──────────

@test "restart rejects --stack" {
  run "${PROJECT_ROOT}/bin/sandbox-start" "$TEST_CONTAINER_NAME" --stack python
  assert_failure
  assert_output --partial "Cannot change"
  assert_output --partial "--stack"
}

@test "restart rejects --slot" {
  run "${PROJECT_ROOT}/bin/sandbox-start" "$TEST_CONTAINER_NAME" --slot 42
  assert_failure
  assert_output --partial "Cannot change"
  assert_output --partial "--slot"
}

@test "restart rejects --from" {
  run "${PROJECT_ROOT}/bin/sandbox-start" "$TEST_CONTAINER_NAME" --from other
  assert_failure
  assert_output --partial "Cannot change"
  assert_output --partial "--from"
}

@test "restart rejects --branch" {
  run "${PROJECT_ROOT}/bin/sandbox-start" "$TEST_CONTAINER_NAME" --branch feature
  assert_failure
  assert_output --partial "Cannot change"
  assert_output --partial "--branch"
}

@test "restart rejects positional repo URL" {
  run "${PROJECT_ROOT}/bin/sandbox-start" "$TEST_CONTAINER_NAME" "https://github.com/org/repo"
  assert_failure
  assert_output --partial "Cannot change"
}

# ── Successful restart (no immutable flags) ────────────────────────

@test "restart succeeds with no immutable flags" {
  run "${PROJECT_ROOT}/bin/sandbox-start" "$TEST_CONTAINER_NAME"
  assert_success
  assert_output --partial "restarted"
}

# ── Domain filtering persistence after restart ─────────────────────

@test "domain filtering metadata survives restart" {
  run get_metadata "agent-${TEST_CONTAINER_NAME}" "restrict-domains"
  assert_success
  assert_output "yes"
}

@test "blocked domain still blocked after restart" {
  run vm_run incus exec "agent-${TEST_CONTAINER_NAME}" -- \
    curl -sf --max-time 10 https://example.com
  assert_failure
}

@test "allowed domain still works after restart" {
  run vm_run incus exec "agent-${TEST_CONTAINER_NAME}" -- \
    curl -s --max-time 10 -o /dev/null -w '%{http_code}' https://api.anthropic.com
  assert_success
  [[ "${output}" =~ ^[0-9]{3}$ ]]
}

# ── Mutable flags on restart ───────────────────────────────────────

@test "CPU and memory changeable on restart" {
  # Stop first
  run "${PROJECT_ROOT}/bin/sandbox-stop" "$TEST_CONTAINER_NAME"
  assert_success

  # Restart with new resource limits
  run "${PROJECT_ROOT}/bin/sandbox-start" "$TEST_CONTAINER_NAME" \
    --cpu 1 --memory 256MB
  assert_success
  assert_output --partial "restarted"

  # Verify new limits
  run vm_exec "incus config get agent-${TEST_CONTAINER_NAME} limits.cpu"
  assert_success
  assert_output "1"

  run vm_exec "incus config get agent-${TEST_CONTAINER_NAME} limits.memory"
  assert_success
  assert_output "256MB"
}
