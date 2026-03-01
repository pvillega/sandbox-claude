#!/usr/bin/env bats
load '../test_helper/common'

# Helper: create a mock executable in TEST_TMPDIR/bin that exits with given code
_mock_cmd() {
  local name="$1" exit_code="${2:-0}" output="${3:-}"
  mkdir -p "${TEST_TMPDIR}/bin"
  cat > "${TEST_TMPDIR}/bin/${name}" << EOF
#!/usr/bin/env bash
${output:+echo "$output"}
exit $exit_code
EOF
  chmod +x "${TEST_TMPDIR}/bin/${name}"
}

# ── macOS path (orb) ────────────────────────────────────────────────

@test "require_vm: macOS succeeds when orb is present and responsive" {
  SANDBOX_PLATFORM="macos"
  _mock_cmd orb 0
  PATH="${TEST_TMPDIR}/bin:${PATH}" run require_vm
  assert_success
}

@test "require_vm: macOS fails when orb command is missing" {
  SANDBOX_PLATFORM="macos"
  # Ensure orb is not on PATH
  PATH="${TEST_TMPDIR}/bin" run require_vm
  assert_failure
  assert_output --partial "orb"
  assert_output --partial "required but not found"
}

@test "require_vm: macOS fails when OrbStack is not running" {
  SANDBOX_PLATFORM="macos"
  _mock_cmd orb 1  # orb exists but 'orb list' returns non-zero
  PATH="${TEST_TMPDIR}/bin:${PATH}" run require_vm
  assert_failure
  assert_output --partial "OrbStack is not running"
}

# ── Linux path (incus) ──────────────────────────────────────────────

@test "require_vm: Linux succeeds when incus is present and responsive" {
  SANDBOX_PLATFORM="linux"
  _mock_cmd incus 0
  PATH="${TEST_TMPDIR}/bin:${PATH}" run require_vm
  assert_success
}

@test "require_vm: Linux fails when incus command is missing" {
  SANDBOX_PLATFORM="linux"
  PATH="${TEST_TMPDIR}/bin" run require_vm
  assert_failure
  assert_output --partial "incus"
  assert_output --partial "required but not found"
}

@test "require_vm: Linux fails when incus is not accessible" {
  SANDBOX_PLATFORM="linux"
  _mock_cmd incus 1  # incus exists but 'incus list' returns non-zero
  PATH="${TEST_TMPDIR}/bin:${PATH}" run require_vm
  assert_failure
  assert_output --partial "Incus is not running or not accessible"
}
