#!/usr/bin/env bats
load '../test_helper/integration'

_name_file() { echo "${BATS_FILE_TMPDIR}/port_exposure_name"; }
_slot_file() { echo "${BATS_FILE_TMPDIR}/port_exposure_slot"; }

setup_file() {
  TEST_CONTAINER_PREFIX="test-${BATS_ROOT_PID:-$$}"
  create_test_container
  echo "$TEST_CONTAINER_NAME" > "$(_name_file)"
  # Retrieve and cache the slot for port calculations
  local slot
  slot=$(vm_exec "incus config get agent-${TEST_CONTAINER_NAME} user.sandbox.slot 2>/dev/null")
  echo "$slot" > "$(_slot_file)"
}

teardown_file() {
  TEST_CONTAINER_NAME=$(<"$(_name_file)")
  destroy_test_container
}

setup() {
  TEST_TMPDIR="$(mktemp -d)"
  TEST_CONTAINER_NAME=$(<"$(_name_file)")
  TEST_SLOT=$(<"$(_slot_file)")
}

@test "sandbox-expose: adds proxy device for TCP port with slot offset" {
  run "${PROJECT_ROOT}/bin/sandbox-expose" "$TEST_CONTAINER_NAME" 5432
  assert_success
  # Verify listen port is offset by slot
  local expected_host_port=$(( 5432 + TEST_SLOT ))
  run vm_exec "incus config device get agent-${TEST_CONTAINER_NAME} port-5432-tcp listen 2>/dev/null"
  assert_success
  assert_output --partial ":${expected_host_port}"
}

@test "sandbox-expose: proxy connects to container port (not host port)" {
  # Device was created in previous test; verify connect uses original port
  run vm_exec "incus config device get agent-${TEST_CONTAINER_NAME} port-5432-tcp connect 2>/dev/null"
  assert_success
  assert_output --partial ":5432"
}

@test "sandbox-expose: adds iptables FORWARD rule" {
  local container_ip
  container_ip=$(get_container_ip)
  run vm_exec "iptables -S FORWARD 2>/dev/null | grep '\\-s ${container_ip}/32.*dport 5432'"
  assert_success
}

@test "sandbox-expose: rejects non-numeric port" {
  run "${PROJECT_ROOT}/bin/sandbox-expose" "$TEST_CONTAINER_NAME" abc
  assert_failure
  assert_output --partial "must be a number"
}

@test "sandbox-expose: rejects invalid protocol" {
  run "${PROJECT_ROOT}/bin/sandbox-expose" "$TEST_CONTAINER_NAME" 3000 ftp
  assert_failure
  assert_output --partial "must be tcp, udp, or both"
}

@test "sandbox-expose: supports UDP protocol" {
  run "${PROJECT_ROOT}/bin/sandbox-expose" "$TEST_CONTAINER_NAME" 5353 udp
  assert_success
  # Verify UDP device connects to original port
  run vm_exec "incus config device get agent-${TEST_CONTAINER_NAME} port-5353-udp connect 2>/dev/null"
  assert_success
  assert_output --partial ":5353"
}

@test "sandbox-expose: 'both' creates TCP and UDP devices" {
  run "${PROJECT_ROOT}/bin/sandbox-expose" "$TEST_CONTAINER_NAME" 6000 both
  assert_success
  # Verify both devices exist with correct connect port
  run vm_exec "incus config device get agent-${TEST_CONTAINER_NAME} port-6000-tcp connect 2>/dev/null"
  assert_success
  assert_output --partial ":6000"
  run vm_exec "incus config device get agent-${TEST_CONTAINER_NAME} port-6000-udp connect 2>/dev/null"
  assert_success
  assert_output --partial ":6000"
}

@test "sandbox-expose: --host-port overrides slot-based computation" {
  run "${PROJECT_ROOT}/bin/sandbox-expose" "$TEST_CONTAINER_NAME" 7777 --host-port 17777
  assert_success
  # Verify listen port uses the override
  run vm_exec "incus config device get agent-${TEST_CONTAINER_NAME} port-7777-tcp listen 2>/dev/null"
  assert_success
  assert_output --partial ":17777"
  # Verify connect still uses container port
  run vm_exec "incus config device get agent-${TEST_CONTAINER_NAME} port-7777-tcp connect 2>/dev/null"
  assert_success
  assert_output --partial ":7777"
}

@test "sandbox-expose: rejects host port out of range" {
  run "${PROJECT_ROOT}/bin/sandbox-expose" "$TEST_CONTAINER_NAME" 65500 --host-port 70000
  assert_failure
  assert_output --partial "out of range"
}

@test "sandbox-expose: rejects non-numeric --host-port" {
  run "${PROJECT_ROOT}/bin/sandbox-expose" "$TEST_CONTAINER_NAME" 4000 --host-port abc
  assert_failure
  assert_output --partial "must be a number"
}
