#!/usr/bin/env bats
load '../test_helper/integration'

_name_file() { echo "${BATS_FILE_TMPDIR}/stop_precond_name"; }

setup_file() {
  local name="test-${BATS_ROOT_PID:-$$}-stopc"
  echo "$name" > "$(_name_file)"

  # Create a container so we can test stop behaviours
  "${PROJECT_ROOT}/bin/sandbox-start" "$name" --stack base
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

# ── Error handling ───────────────────────────────────────────────────

@test "sandbox-stop: fails for non-existent container" {
  run "${PROJECT_ROOT}/bin/sandbox-stop" "nonexistent-container-xyz-99"
  assert_failure
  assert_output --partial "not found"
}

@test "sandbox-stop: requires a name argument" {
  run "${PROJECT_ROOT}/bin/sandbox-stop"
  assert_failure
}

# ── Verify require_vm is sufficient (no require_sandbox needed) ──────

@test "sandbox-stop: succeeds with valid running container" {
  run "${PROJECT_ROOT}/bin/sandbox-stop" "$TEST_CONTAINER_NAME"
  assert_success
  assert_output --partial "Stopped"
}

@test "sandbox-stop: container is stopped after stop" {
  run vm_exec "incus info agent-${TEST_CONTAINER_NAME} 2>/dev/null | grep 'Status:' | awk '{print \$2}'"
  assert_success
  assert_output "STOPPED"
}

@test "sandbox-stop: is idempotent on already-stopped container" {
  # Container was stopped in previous test; stopping again should still succeed
  run "${PROJECT_ROOT}/bin/sandbox-stop" "$TEST_CONTAINER_NAME"
  assert_success
}

@test "sandbox-stop --rm: removes container entirely" {
  # Restart first so we have a clean running container to remove
  "${PROJECT_ROOT}/bin/sandbox-start" "$TEST_CONTAINER_NAME"

  run "${PROJECT_ROOT}/bin/sandbox-stop" "$TEST_CONTAINER_NAME" --rm
  assert_success
  assert_output --partial "Deleted"
}

@test "sandbox-stop --rm: container no longer exists" {
  run vm_exec "incus info agent-${TEST_CONTAINER_NAME} 2>&1"
  assert_failure
}
