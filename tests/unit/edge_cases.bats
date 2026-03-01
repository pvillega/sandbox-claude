#!/usr/bin/env bats
load '../test_helper/common'

@test "container_name: empty string is rejected" {
  run container_name ""
  assert_failure
}

@test "container_name: name with dots" {
  run container_name "v1.2.3"
  assert_success
  assert_output "agent-v1.2.3"
}

@test "parse_repo_nwo: URL with extra path segments" {
  run parse_repo_nwo "https://github.com/org/repo/tree/main"
  assert_success
  assert_output "org/repo/tree/main"
}

@test "parse_repo_nwo: bare org/repo.git without github.com" {
  run parse_repo_nwo "org/repo.git"
  assert_success
  assert_output "org/repo"
}

@test "ssh_port: slot 0 returns 2200" {
  run ssh_port 0
  assert_success
  assert_output "2200"
}

@test "parse_domains_file: file with only comments produces empty output" {
  cat > "${TEST_TMPDIR}/comments-only.txt" << 'EOF'
# comment one
# comment two
# comment three
EOF
  run parse_domains_file "${TEST_TMPDIR}/comments-only.txt"
  assert_success
  assert_output ""
}

@test "parse_domains_file: empty file produces empty output" {
  touch "${TEST_TMPDIR}/empty.txt"
  run parse_domains_file "${TEST_TMPDIR}/empty.txt"
  assert_success
  assert_output ""
}
