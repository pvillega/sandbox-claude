#!/usr/bin/env bats
load '../test_helper/common'

@test "container_name: simple name" {
  run container_name "myproject"
  assert_success
  assert_output "agent-myproject"
}

@test "container_name: name with hyphens" {
  run container_name "my-project-v2"
  assert_success
  assert_output "agent-my-project-v2"
}

@test "container_name: rejects name with semicolons" {
  run container_name "foo;bar"
  assert_failure
}

@test "container_name: rejects name with spaces" {
  run container_name "foo bar"
  assert_failure
}

@test "container_name: rejects empty string" {
  run container_name ""
  assert_failure
}
