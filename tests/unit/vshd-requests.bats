#!/usr/bin/env bats
# vshd request handling: parsing, list, proxy clients, modules, logging.

load helpers

setup() { setup_vshd; }

@test "empty request prints usage" {
  vshd_as alice ""
  [ "$status" -eq 0 ]
  [[ "$output" == *"VSH daemon"* ]]
}

@test "unknown request prints usage and the offending input" {
  vshd_as alice "frobnicate now"
  [[ "$output" == *"VSH daemon"* ]]
  [[ "$output" == *"Invalid input: frobnicate now"* ]]
}

@test "non-printable characters are rejected before anything runs" {
  vshd_as alice $'run lxc:web01.vsh.test echo \x01pwned'
  [[ "$output" == *"INVALID INPUT: run lxc:web01.vsh.test echo #pwned"* ]]
  [ ! -s "$ROOT/log/calls" ]
}

@test "newline injection is rejected" {
  vshd_as alice $'list\nhostrun id'
  [[ "$output" == *"INVALID INPUT"* ]]
  [[ "$output" != *"uid="* ]]
}

@test "list prints LXC containers and proxy clients" {
  vshd_as alice "list"
  [ "$status" -eq 0 ]
  [[ "$output" == *"vshhost1 web01.vsh.test lxc:web01.vsh.test RUNNING"* ]]
  [[ "$output" == *"vshhost1 app01.vsh.test lxc:app01.vsh.test STOPPED"* ]]
  [[ "$output" == *$'root@vshhost1 gw\tssh:target proxy'* ]]
  [[ "$output" == *$'root@vshhost1 gw2\tssh:target:2222 proxy'* ]]
}

@test "list without a proxy-clients file lists containers only" {
  rm "$ROOT/opt/vsh/etc/proxy-clients"
  vshd_as alice "list"
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | wc -l)" -eq 3 ]
}

@test "proxy client is reached with ssh as root" {
  vshd_as alice "run ssh:target hostname"
  [ "$status" -eq 0 ]
  grep -qx "ssh root@target hostname" "$ROOT/log/calls"
}

@test "proxy client on a non-standard port uses -p" {
  vshd_as bob "run ssh:target:2222 hostname"
  [ "$status" -eq 0 ]
  grep -qx "ssh root@target -p 2222 hostname" "$ROOT/log/calls"
}

@test "proxy client permission is checked against its alias" {
  # bob has gw2 but not gw
  vshd_as bob "run ssh:target hostname"
  [ "$status" -eq 1 ]
  [[ "$output" == *"run permission denied for bob@gw"* ]]
}

@test "proxy client not in proxy-clients is denied" {
  vshd_as alice "run ssh:elsewhere id"
  [ "$status" -eq 1 ]
  [[ "$output" == *"run permission denied for alice@elsewhere"* ]]
}

@test "stdin is passed through to the container command" {
  vshd_as alice "run lxc:web01.vsh.test cat" <<< "piped"
  [[ "$output" == *piped* ]]
}

@test "module runs when permitted and is denied otherwise" {
  cat > "$ROOT/opt/vsh/modulesd/hello" <<'EOF'
echo "hello from module, args: $ccmd"
EOF
  vshd_as alice "module hello a b"
  [ "$status" -eq 0 ]
  [[ "$output" == *"hello from module, args: a b"* ]]

  vshd_as bob "module hello"
  [ "$status" -eq 1 ]
  [[ "$output" == *"error: module hello denied for bob"* ]]
}

@test "every request is logged at info, denials at err" {
  vshd_as alice "run lxc:web01.vsh.test true"
  vshd_as bob "run lxc:web01.vsh.test true"
  grep -q "^-p info vshd ([0-9]*): ARG: user=alice CMD: run lxc:web01.vsh.test true$" "$ROOT/log/syslog"
  grep -q "^-p info vshd ([0-9]*): run alice web01.vsh.test (web01.vsh.test)$" "$ROOT/log/syslog"
  grep -q "^-p info vshd ([0-9]*): end session: alice$" "$ROOT/log/syslog"
  grep -q "^-p err vshd ([0-9]*): error: run permission denied for bob@web01.vsh.test" "$ROOT/log/syslog"
}

############################
# Known bugs
############################

glob_expands_in_container() {
  touch "$ROOT/work/ONLY-ON-HOST"
  vshd_as alice "run lxc:web01.vsh.test echo *"
  [[ "$output" == "*" ]]
}

@test "KB-2: globs in a request expand on the vsh-host, not in the container" {
  expect_known_bug KB-2 glob_expands_in_container
}

module_stays_in_moduledir() {
  echo 'echo ESCAPED-MODULEDIR' > "$ROOT/opt/vsh/etc/not-a-module"
  vshd_as alice "module ../etc/not-a-module"
  [[ "$output" != *ESCAPED-MODULEDIR* ]]
}

@test "KB-3: module name can traverse out of modulesd" {
  expect_known_bug KB-3 module_stays_in_moduledir
}

vsh_proxy_checked_by_name() {
  # A vsh-proxied client: vshd asks `vsh -lll` for its name and should
  # check permissions against that name.
  printf '#!/bin/bash\necho "vshhost9 inner.vsh.test inner RUNNING"\n' > "$ROOT/opt/vsh/bin/vsh"
  chmod +x "$ROOT/opt/vsh/bin/vsh"
  use_ini <<'EOF'
[groups]
[containers]
inner.vsh.test:alice
EOF
  vshd_as alice "run vsh:inner true"
  [[ "$output" != *"permission denied"* ]]
}

@test "KB-4: vsh: proxy targets are checked against the id, not the name" {
  expect_known_bug KB-4 vsh_proxy_checked_by_name
}

exit_status_propagates() {
  vshd_as alice "run lxc:web01.vsh.test false"
  [ "$status" -ne 0 ]
}

@test "KB-5: vshd exits 0 even when the container command fails" {
  expect_known_bug KB-5 exit_status_propagates
}
