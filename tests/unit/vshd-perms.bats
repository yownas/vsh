#!/usr/bin/env bats
# vshd authorization: [groups], [containers], [hosts], [operations], roles.

load helpers

setup() { setup_vshd; }

@test "wheel member can run a command in an allowed container" {
  vshd_as alice "run lxc:web01.vsh.test echo hello"
  [ "$status" -eq 0 ]
  [[ "$output" == *hello* ]]
  grep -qx "lxc-attach -n web01.vsh.test -- echo hello" "$ROOT/log/calls"
}

@test "user listed directly on a container is allowed" {
  vshd_as bob "run lxc:db01.vsh.test echo hello"
  [ "$status" -eq 0 ]
  grep -q "lxc-attach -n db01.vsh.test" "$ROOT/log/calls"
}

@test "user is denied a container they are not listed on" {
  vshd_as bob "run lxc:web01.vsh.test echo hello"
  [ "$status" -eq 1 ]
  [[ "$output" == *"error: run permission denied for bob@web01.vsh.test"* ]]
  ! grep -q lxc-attach "$ROOT/log/calls"
}

@test "unknown user is denied" {
  vshd_as mallory "run lxc:web01.vsh.test id"
  [ "$status" -eq 1 ]
  [[ "$output" == *"permission denied"* ]]
}

@test "user name prefix does not match a longer name" {
  vshd_as ali "run lxc:web01.vsh.test id"
  [[ "$output" == *"run permission denied for ali@"* ]]
  vshd_as bo "run lxc:db01.vsh.test id"
  [[ "$output" == *"run permission denied for bo@"* ]]
}

@test "user name suffix does not match a longer name" {
  vshd_as lice "run lxc:web01.vsh.test id"
  [[ "$output" == *"run permission denied for lice@"* ]]
}

@test "container name prefix does not match a longer name" {
  # bob may use db01.vsh.test, not a container called db01.vsh
  echo "db01.vsh RUNNING" >> "$ROOT/log/lxc"
  vshd_as bob "run lxc:db01.vsh id"
  [[ "$output" == *"run permission denied for bob@db01.vsh"* ]]
}

@test "hostrun with a command is allowed for [hosts] *:@wheel" {
  vshd_as alice "hostrun echo on-host"
  [ "$status" -eq 0 ]
  [[ "$output" == *on-host* ]]
}

@test "hostrun is denied for users not in [hosts]" {
  vshd_as bob "hostrun id"
  [ "$status" -eq 1 ]
  [[ "$output" == *"error: hostrun permission denied for bob@vshhost1"* ]]
}

@test "start/stop needs the admins role" {
  vshd_as alice "start app01.vsh.test"
  [ "$status" -eq 1 ]
  [[ "$output" == *"error: start app01.vsh.test denied for alice"* ]]

  vshd_as alice+admin "start app01.vsh.test"
  [ "$status" -eq 0 ]
  grep -qx "lxc-start -n app01.vsh.test -d" "$ROOT/log/calls"

  vshd_as alice+admin "stop web01.vsh.test"
  [ "$status" -eq 0 ]
  grep -qx "lxc-stop -n web01.vsh.test" "$ROOT/log/calls"
}

@test "role key inherits group membership of its own entry only" {
  # alice+admin is in wheel explicitly, plain alice is not in admins.
  vshd_as alice+admin "run lxc:web01.vsh.test true"
  [ "$status" -eq 0 ]
  vshd_as alice "stop web01.vsh.test"
  [ "$status" -eq 1 ]
}

@test "role listed directly (not via group) has its + escaped" {
  use_ini <<'EOF'
[groups]
[containers]
web01.vsh.test:alice+admin
EOF
  vshd_as alice+admin "run lxc:web01.vsh.test true"
  [ "$status" -eq 0 ]
  # + must not act as a regex quantifier
  vshd_as aliceadmin "run lxc:web01.vsh.test true"
  [ "$status" -eq 1 ]
  vshd_as alice "run lxc:web01.vsh.test true"
  [ "$status" -eq 1 ]
}

@test "move is checked before the LXC backend refuses it" {
  vshd_as alice "move lxc:app01.vsh.test vshhost1"
  [ "$status" -eq 1 ]
  [[ "$output" == *"move denied for alice"* ]]

  vshd_as alice+admin "move lxc:app01.vsh.test vshhost1"
  [[ "$output" == *"Migrating LXC containers not implemented"* ]]
}

move_by_name_reports_unsupported() {
  vshd_as alice+admin "move app01.vsh.test vshhost1"
  [[ "$output" == *"not implemented"* ]] || [ "$status" -ne 0 ]
}

@test "KB-6: move by container name on an LXC host fails silently" {
  # The client sends the name, not lxc:<name>, so the LXC guard never
  # triggers and nothing at all happens.
  expect_known_bug KB-6 move_by_name_reports_unsupported
}

@test "runas user on an LXC container is refused with a message" {
  use_ini <<'EOF'
[groups]
[containers]
db01.vsh.test:bob=app
EOF
  vshd_as bob "run lxc:db01.vsh.test id"
  [[ "$output" == *"Entering LXC containers as a user not implemented"* ]]
  ! grep -q lxc-attach "$ROOT/log/calls"
}

@test "runas user for a role listed directly is found" {
  use_ini <<'EOF'
[groups]
[containers]
db01.vsh.test:alice+admin=app
EOF
  vshd_as alice+admin "run lxc:db01.vsh.test id"
  [[ "$output" == *"Entering LXC containers as a user not implemented"* ]]
  ! grep -q lxc-attach "$ROOT/log/calls"
}

regex_container_is_denied() {
  vshd_as bob "run lxc:.* true"
  [[ "$output" == *"run permission denied for bob@"* ]] && ! grep -q "run bob " "$ROOT/log/syslog"
}

@test "KB-1: container name from the client is used as a regex in the permission check" {
  # bob is only allowed on db01 and gw2, but '.*' matches their lines in
  # vshd.ini (and then every line of proxy-clients).
  expect_known_bug KB-1 regex_container_is_denied
}

alternation_container_is_denied() {
  vshd_as bob "run ssh:target|db01.vsh.test true"
  [[ "$output" == *"run permission denied for bob@"* ]] && ! grep -q "^ssh " "$ROOT/log/calls"
}

@test "KB-1: regex alternation lets a proxy target pass another container's check" {
  expect_known_bug KB-1 alternation_container_is_denied
}
