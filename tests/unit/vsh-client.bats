#!/usr/bin/env bats
# vsh client: argument parsing, statefile, and the requests it sends.
#
# ssh is a stub: `list` answers with a fixed container list per host, any
# other request is recorded in $CALLS as "ssh <argv>".

load helpers

setup() {
  setup_vsh
  # Most tests start from a populated statefile, as after any earlier vsh run.
  vsh -l > /dev/null
}

me() { whoami; }

@test "no arguments prints usage" {
  run vsh
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage:"* ]]
}

@test "unknown option prints usage" {
  run vsh -Z
  [[ "$output" == *"Usage:"* ]]
}

@test "-H without a host lists the hostfile, skipping comments" {
  printf '# comment\nvshhost1\nvshhost2 extra\n' > "$HOME/.vsh/hosts"
  run vsh -H
  [ "$status" -eq 0 ]
  [ "$output" = $'vshhost1\nvshhost2' ]
}

@test "-k without a suffix lists keys" {
  run vsh -k
  [[ "$output" == *"Keylist:"* ]]
  [[ "$output" == *admin* ]]
  [[ "$output" == *user* ]]
}

@test "missing arguments are reported" {
  run vsh -r
  [[ "$output" == *"ERROR: container name needed."* ]]
  run vsh -o
  [[ "$output" == *"ERROR: operation needed."* ]]
  run vsh -M
  [[ "$output" == *"ERROR: module name needed."* ]]
}

@test "missing hostfile is an error" {
  rm "$HOME/.vsh/hosts"
  run vsh web01.vsh.test
  [ "$status" -eq 1 ]
  [[ "$output" == *"hosts missing or empty."* ]]
}

@test "missing key is an error" {
  rm "$HOME/.vsh/keys/vsh-$(me)-user"
  run vsh web01.vsh.test
  [ "$status" -eq 1 ]
  [[ "$output" == *"Generate key-pair with"* ]]
}

@test "-l merges container lists from all hosts into the statefile" {
  run vsh -l
  [ "$status" -eq 0 ]
  [ "$output" = $'web01.vsh.test\ndb01.vsh.test\napp01.vsh.test\ngw' ]
  grep -q "^vshhost2 gw ssh:target proxy$" "$HOME/.vsh/var/ctstate"
}

@test "-ll and -lll formats" {
  run vsh -ll
  [[ "$output" == *"web01.vsh.test@vshhost1"* ]]
  [[ "$output" == *"gw@vshhost2"* ]]
  run vsh -lll
  [[ "$output" =~ vshhost1\ +web01.vsh.test\ +lxc:web01.vsh.test\ RUNNING ]]
}

@test "-u uses the cached statefile without asking the hosts" {
  echo "vshhost1 cached.vsh.test lxc:cached.vsh.test RUNNING" > "$HOME/.vsh/var/ctstate"
  run vsh -u -l
  [ "$output" = "cached.vsh.test" ]
  VSH_UPDATE=0 run vsh -l
  [ "$output" = "cached.vsh.test" ]
}

@test "run sends 'run <path> <cmd>' to the container's host with the user key" {
  run vsh web01.vsh.test uname -a
  [ "$status" -eq 0 ]
  grep -q -- "-i $HOME/.vsh/keys/vsh-$(me)-user root@vshhost1 run lxc:web01.vsh.test uname -a$" "$CALLS"
}

@test "ssh is non-interactive and fails fast" {
  run vsh web01.vsh.test true
  grep -q -- "^ssh -o PasswordAuthentication=no -o NumberOfPasswordPrompts=0 -o ConnectTimeout=4 " "$CALLS"
}

@test "a shell (no command) requests a tty" {
  run vsh app01.vsh.test
  grep -q -- " -t root@vshhost2 run lxc:app01.vsh.test$" "$CALLS"
}

@test "-k selects the role key" {
  run vsh -k admin web01.vsh.test true
  grep -q -- "-i $HOME/.vsh/keys/vsh-$(me)-admin root@vshhost1 " "$CALLS"
  VSH_KEY=admin run vsh web01.vsh.test true
  [ "$(grep -c -- "vsh-$(me)-admin root@" "$CALLS")" -eq 2 ]
}

@test "proxy clients are run on the host that lists them" {
  run vsh gw hostname
  grep -q -- "root@vshhost2 run ssh:target hostname$" "$CALLS"
}

@test "a vsh-host name runs on the host itself" {
  run vsh vshhost1 uptime
  grep -q -- "root@vshhost1 hostrun uptime$" "$CALLS"
}

@test "-H and -h run on a host" {
  run vsh -H vshhost2 uptime
  grep -q -- "root@vshhost2 hostrun uptime$" "$CALLS"
  : > "$CALLS"
  run vsh -h db01.vsh.test uptime
  grep -q -- "root@vshhost1 hostrun uptime$" "$CALLS"
}

@test "user@host in the hostfile overrides root" {
  printf 'vsh@vshhost1\n' > "$HOME/.vsh/hosts"
  run vsh -H vsh@vshhost1 id
  grep -q -- " vsh@vshhost1 hostrun id$" "$CALLS"
}

@test "unknown container is reported" {
  run vsh nosuch.vsh.test true
  [ "$status" -eq 1 ]
  [[ "$output" == *"getctname: Can not find container nosuch.vsh.test"* ]]
  [ ! -s "$CALLS" ]
}

@test "-p -o athosts prefixes output with the host" {
  run vsh -p -o athosts uptime
  [[ "$output" == *"vshhost1 remote(vshhost1): hostrun uptime"* ]]
  [[ "$output" == *"vshhost2 remote(vshhost2): hostrun uptime"* ]]
}

@test "-o atct runs on every container read from stdin, once each" {
  run vsh -p -o atct hostname <<< $'web01.vsh.test\nweb01.vsh.test\napp01.vsh.test'
  [ "$(grep -c "run lxc:web01.vsh.test hostname" "$CALLS")" -eq 1 ]
  [ "$(grep -c "run lxc:app01.vsh.test hostname" "$CALLS")" -eq 1 ]
  [[ "$output" == *"web01.vsh.test remote(vshhost1)"* ]]
}

@test "-o start/stop/move send the container name to its host" {
  run vsh -k admin -o stop app01.vsh.test
  grep -q -- "root@vshhost2 stop app01.vsh.test$" "$CALLS"
  run vsh -k admin -o move app01.vsh.test vshhost1
  grep -q -- "root@vshhost2 move app01.vsh.test vshhost1$" "$CALLS"
}

@test "-o with an unknown operation is an error" {
  run vsh -o frob x
  [ "$status" -eq 1 ]
  [[ "$output" == *"operation: Unknown command: frob"* ]]
}

@test "scp through vsh (vcp) is rewritten to a plain run" {
  run vsh -x -oForwardAgent=no -oPermitLocalCommand=no -oClearAllForwardings=yes -- web01.vsh.test scp -t /tmp
  grep -q -- "root@vshhost1 run lxc:web01.vsh.test scp -t /tmp$" "$CALLS"
}

@test "-M runs a client-side module" {
  mkdir -p "$HOME/.vsh/modules"
  cp "$VSH_SRC/modules/list" "$HOME/.vsh/modules/"
  run vsh -M list
  [[ "$output" == *"==== list ===="* ]]
  run vsh -M nosuch
  [[ "$output" == *"No module: nosuch"* ]]
}

@test "-g X11 creates a passphrase-less key and no dist key" {
  run vsh -q -g X11
  [ -s "$HOME/.vsh/keys/vsh-$(me)-X11" ]
  [ ! -e "$HOME/.vsh/keys/vsh-$(me)-X11.dist.pub" ]
}

@test "-g refuses to overwrite an existing key" {
  run vsh -g user
  [ "$status" -eq 1 ]
  [[ "$output" == *"exists."* ]]
}

client_exit_status_propagates() {
  VSH_TEST_EXIT=3 run vsh web01.vsh.test false
  [ "$status" -eq 3 ]
}

@test "KB-5: vsh exits 0 even when the remote command fails" {
  expect_known_bug KB-5 client_exit_status_propagates
}

first_use_without_statefile_works() {
  rm -f "$HOME/.vsh/var/ctstate"
  run vsh gw hostname
  grep -q -- "root@vshhost2 run ssh:target hostname$" "$CALLS"
}

@test "KB-7: a container unknown to DNS fails until the statefile has been refreshed" {
  # main resolves the name (vsh_getctname) before the run action refreshes
  # the statefile, so the first `vsh gw` on a fresh workstation fails.
  expect_known_bug KB-7 first_use_without_statefile_works
}
