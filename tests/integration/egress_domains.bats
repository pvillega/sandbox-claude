#!/usr/bin/env bats
load '../test_helper/integration'

# Persist the container name so all tests (which run in subprocesses) share it.
_name_file() { echo "${BATS_FILE_TMPDIR}/egress_domains_name"; }
_fixture_dir_file() { echo "${BATS_FILE_TMPDIR}/egress_domains_fixture_dir"; }

setup_file() {
  # Resolve FIXTURE_DIR here (file scope) and persist for subprocesses
  local fixture_dir
  fixture_dir="$(cd "$(dirname "${BATS_TEST_FILENAME}")/../fixtures" && pwd)"
  echo "$fixture_dir" > "$(_fixture_dir_file)"

  # Override the prefix so create_test_container computes a stable name
  TEST_CONTAINER_PREFIX="test-${BATS_ROOT_PID:-$$}"
  create_test_container --domains-file "${fixture_dir}/test-allowlist.txt"
  # Persist the name that create_test_container computed
  echo "$TEST_CONTAINER_NAME" > "$(_name_file)"
}

teardown_file() {
  TEST_CONTAINER_NAME=$(<"$(_name_file)")
  destroy_test_container
}

# Restore the container name in each test subprocess
setup() {
  TEST_TMPDIR="$(mktemp -d)"
  TEST_CONTAINER_NAME=$(<"$(_name_file)")
}

@test "allowed domain: HTTPS to api.anthropic.com connects" {
  # We expect a TCP connection to succeed (HTTP-level response may be 4xx, that's fine)
  run container_exec curl -s --max-time 10 -o /dev/null -w '%{http_code}' https://api.anthropic.com
  assert_success
  # Any HTTP response code means the TLS handshake + TCP connection worked
  [[ "${output}" =~ ^[0-9]{3}$ ]]
}

@test "allowed domain: HTTPS to registry.npmjs.org connects" {
  run container_exec curl -s --max-time 10 -o /dev/null -w '%{http_code}' https://registry.npmjs.org
  assert_success
  [[ "${output}" =~ ^[0-9]{3}$ ]]
}

@test "blocked domain: HTTPS to example.com is rejected" {
  run container_exec curl -sf --max-time 10 https://example.com
  assert_failure
}

@test "blocked domain: HTTPS to google.com is rejected" {
  run container_exec curl -sf --max-time 10 https://google.com
  assert_failure
}

@test "blocked domain: HTTPS to evil.example.org is rejected" {
  run container_exec curl -sf --max-time 10 https://evil.example.org
  assert_failure
}

@test "QUIC bypass prevented: UDP 443 is dropped" {
  # Verify that an iptables DROP rule for UDP 443 exists for this container's IP.
  # We check from the VM side because UDP send from inside the container always
  # returns success (UDP is connectionless — dropped packets don't cause send errors).
  local container_ip
  container_ip=$(get_container_ip)
  run vm_exec "iptables -S FORWARD 2>/dev/null | grep -q '\\-s ${container_ip}/32.*udp.*dport 443.*DROP'"
  assert_success
}

@test "DNS still works in restricted container" {
  run container_exec bash -c 'getent ahosts example.com 2>/dev/null | head -1'
  assert_success
  assert_output --regexp '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+'
}

@test "HTTP (port 80) to blocked domain is rejected" {
  # Squid also redirects port 80 traffic for restricted containers
  run container_exec curl -sf --max-time 10 http://example.com
  assert_failure
}
