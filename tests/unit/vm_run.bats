#!/usr/bin/env bats
load '../test_helper/common'

# Create mock executables that record their arguments to a file
_mock_cmd() {
  local name="$1"
  mkdir -p "${TEST_TMPDIR}/bin"
  cat > "${TEST_TMPDIR}/bin/${name}" << 'EOF'
#!/usr/bin/env bash
# Record all arguments to a shared file
echo "$0 $*" >> "${MOCK_LOG}"
EOF
  chmod +x "${TEST_TMPDIR}/bin/${name}"
}

setup() {
  TEST_TMPDIR="$(mktemp -d)"
  export MOCK_LOG="${TEST_TMPDIR}/calls.log"
  : > "$MOCK_LOG"
}

teardown() {
  rm -rf "$TEST_TMPDIR"
}

# ── vm_run: Linux path ──────────────────────────────────────────────

@test "vm_run: Linux prepends sudo to command" {
  SANDBOX_PLATFORM="linux"
  _mock_cmd sudo
  PATH="${TEST_TMPDIR}/bin:${PATH}" vm_run echo hello
  run cat "$MOCK_LOG"
  assert_output --partial "sudo echo hello"
}

@test "vm_run: Linux passes all arguments through sudo" {
  SANDBOX_PLATFORM="linux"
  _mock_cmd sudo
  PATH="${TEST_TMPDIR}/bin:${PATH}" vm_run ls -la /tmp
  run cat "$MOCK_LOG"
  assert_output --partial "sudo ls -la /tmp"
}

# ── vm_run: macOS path ──────────────────────────────────────────────

@test "vm_run: macOS calls orb run with machine name and sudo" {
  SANDBOX_PLATFORM="macos"
  _mock_cmd orb
  PATH="${TEST_TMPDIR}/bin:${PATH}" vm_run echo hello
  run cat "$MOCK_LOG"
  assert_output --partial "orb run -m ${SANDBOX_MACHINE} sudo echo hello"
}

@test "vm_run: macOS passes all arguments after sudo" {
  SANDBOX_PLATFORM="macos"
  _mock_cmd orb
  PATH="${TEST_TMPDIR}/bin:${PATH}" vm_run ls -la /tmp
  run cat "$MOCK_LOG"
  assert_output --partial "orb run -m ${SANDBOX_MACHINE} sudo ls -la /tmp"
}

# ── vm_exec: delegates to vm_run bash -c ─────────────────────────────

@test "vm_exec: delegates to vm_run with bash -c on Linux" {
  SANDBOX_PLATFORM="linux"
  _mock_cmd sudo
  PATH="${TEST_TMPDIR}/bin:${PATH}" vm_exec "echo hello world"
  run cat "$MOCK_LOG"
  assert_output --partial "sudo bash -c echo hello world"
}

@test "vm_exec: delegates to vm_run with bash -c on macOS" {
  SANDBOX_PLATFORM="macos"
  _mock_cmd orb
  PATH="${TEST_TMPDIR}/bin:${PATH}" vm_exec "echo hello world"
  run cat "$MOCK_LOG"
  assert_output --partial "orb run -m ${SANDBOX_MACHINE} sudo bash -c echo hello world"
}
