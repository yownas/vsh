# Shared helpers for the unit tier.
#
# vshd is run for real (vshd + libexec/vshd-Linux) inside bubblewrap, with
# /opt/vsh bind-mounted from a per-test directory. Only the tools vshd talks
# to (lxc-*, logger, ssh) are replaced by stubs that record their argv.
#
# The vsh client needs no sandbox: it is pointed at a temporary $HOME and
# stub ssh/ssh-add/host binaries.

# Where the scripts under test come from: the flake package in CI, the working
# tree when run from a dev shell.
VSH_SRC=${VSH_PKG:-$(cd "$BATS_TEST_DIRNAME/../.." && pwd)}
FIXTURES=$(cd "$BATS_TEST_DIRNAME/../fixtures" && pwd)

_src() {
  # Package layout has bin/, the source tree has the scripts at the top.
  if [ -e "$VSH_SRC/bin/$1" ]; then echo "$VSH_SRC/bin/$1"; else echo "$VSH_SRC/$1"; fi
}

############################
# Known bugs
############################

# expect_known_bug <id> <function> [args...]
#
# <function> asserts the *correct* behaviour. While the bug exists it fails
# and the test passes. Once someone fixes the bug the function succeeds and
# this fails, telling them to turn the marker into a plain assertion and
# close the entry in TODO.md.
expect_known_bug() {
  local id=$1
  shift
  if ( "$@" ) > "$BATS_TEST_TMPDIR/known-bug.out" 2>&1; then
    echo "$id appears to be FIXED: replace expect_known_bug with a plain assertion and update TODO.md" >&2
    return 1
  fi
  # A broken harness must not count as "bug still present".
  if [ -e "$BATS_TEST_TMPDIR/infra-error" ]; then
    cat "$BATS_TEST_TMPDIR/known-bug.out" >&2
    return 1
  fi
  echo "# $id still present" >&3
}

############################
# vshd sandbox
############################

setup_vshd() {
  ROOT=$BATS_TEST_TMPDIR/root
  STUBS=$BATS_TEST_TMPDIR/stubs
  mkdir -p "$ROOT"/opt/vsh/{bin,etc,libexec,modulesd} "$ROOT"/log "$ROOT"/work "$STUBS"

  cp "$(_src vshd)" "$ROOT/opt/vsh/bin/vshd"
  cp "$VSH_SRC/libexec/vshd-Linux" "$ROOT/opt/vsh/libexec/"
  cp "$VSH_SRC"/modulesd/* "$ROOT/opt/vsh/modulesd/"
  cp "$FIXTURES/vshd.ini" "$FIXTURES/proxy-clients" "$ROOT/opt/vsh/etc/"
  chmod -R u+w "$ROOT/opt"
  touch "$ROOT/log/calls" "$ROOT/log/syslog"
  # sshd runs vshd as root
  echo "root:x:0:0:root:/root:/bin/bash" > "$ROOT/passwd"
  echo "root:x:0:" > "$ROOT/group"

  # Containers the fake LXC knows about: "<name> <state>"
  cat > "$ROOT/log/lxc" <<EOF
web01.vsh.test RUNNING
db01.vsh.test RUNNING
app01.vsh.test STOPPED
EOF

  _stub logger 'echo "$*" >> /log/syslog'
  _stub ssh 'echo "ssh $*" >> /log/calls; echo "ssh-ran $*"'
  _stub lxc-ls 'echo "NAME NAME STATE"; awk "{print \$1, \$1, \$2}" /log/lxc'
  _stub lxc-info '
    while [ $# -gt 0 ]; do [ "$1" = -n ] && n=$2; shift; done
    grep -qx "$n [A-Z]*" /log/lxc || { echo "$n doesn'"'"'t exist" >&2; exit 1; }
    echo "Name:           $n"'
  _stub lxc-start 'echo "lxc-start $*" >> /log/calls'
  _stub lxc-stop 'echo "lxc-stop $*" >> /log/calls'
  # Runs the command on the "host" so exit codes and stdin are realistic.
  _stub lxc-attach '
    echo "lxc-attach $*" >> /log/calls
    while [ $# -gt 0 ] && [ "$1" != -- ]; do shift; done; shift
    "$@"'
}

_stub() {
  printf '#!%s\n%s\n' "$(readlink -f "$(command -v bash)")" "$2" > "$STUBS/$1"
  chmod +x "$STUBS/$1"
}

# use_ini: replace vshd.ini with stdin
use_ini() {
  cat > "$ROOT/opt/vsh/etc/vshd.ini"
}

# vshd_as <user> <original-command>
# Runs vshd as sshd would for a key with command="/opt/vsh/bin/vshd user=<user>".
# Sets $status/$output via bats `run`.
vshd_as() {
  local user=$1 cmd=$2 bash path
  bash=$(readlink -f "$(command -v bash)")
  # Only store paths exist inside the sandbox.
  path=$(tr : '\n' <<< "$PATH" | grep '^/nix/store/' | paste -sd:)
  run bwrap \
    --ro-bind /nix /nix \
    --bind "$ROOT/opt" /opt \
    --bind "$ROOT/log" /log \
    --bind "$ROOT/work" /root \
    --ro-bind "$STUBS" /stubs \
    --symlink "$bash" /bin/bash \
    --symlink "$bash" /bin/sh \
    --ro-bind "$ROOT/passwd" /etc/passwd \
    --ro-bind "$ROOT/group" /etc/group \
    --dev /dev --proc /proc --tmpfs /tmp \
    --unshare-user --uid 0 --gid 0 \
    --unshare-uts --hostname vshhost1 \
    --chdir /root \
    --clearenv \
    --setenv PATH "/stubs:$path" \
    --setenv SSH_ORIGINAL_COMMAND "$cmd" \
    /opt/vsh/bin/vshd "user=$user"
  if [[ "$output" == bwrap:* || "$output" =~ /opt/vsh/[a-z/-]+:\ line\ [0-9]+:\ [^\ ]+:\ command\ not\ found ]]; then
    echo "sandbox failed: $output" | tee -a "$BATS_TEST_TMPDIR/infra-error" >&2
    return 1
  fi
}

calls() { cat "$ROOT/log/calls"; }
syslog() { cat "$ROOT/log/syslog"; }

############################
# vsh client sandbox
############################

setup_vsh() {
  export HOME=$BATS_TEST_TMPDIR/home
  CLIENT_BIN=$BATS_TEST_TMPDIR/client-bin
  STUBS=$BATS_TEST_TMPDIR/stubs
  CALLS=$BATS_TEST_TMPDIR/ssh-calls
  mkdir -p "$HOME/.vsh/keys" "$HOME/.vsh/var" "$CLIENT_BIN" "$STUBS"
  # The Nix build sandbox has no /usr/bin/env; only the shebang line differs.
  { echo "#!$(readlink -f "$(command -v bash)")"; tail -n +2 "$(_src vsh)"; } > "$CLIENT_BIN/vsh"
  chmod +x "$CLIENT_BIN/vsh"
  touch "$CALLS"
  export VSH_TEST_CALLS=$CALLS
  export VSH_TEST_EXIT=0

  printf 'vshhost1\nvshhost2\n' > "$HOME/.vsh/hosts"
  for k in user admin; do
    echo PRIVATE > "$HOME/.vsh/keys/vsh-$(whoami)-$k"
    echo "ssh-ed25519 AAAA vsh-$(whoami)-$k" > "$HOME/.vsh/keys/vsh-$(whoami)-$k.pub"
    echo "command=\"/opt/vsh/bin/vshd user=$(whoami)\" ssh-ed25519 AAAA" > "$HOME/.vsh/keys/vsh-$(whoami)-$k.dist.pub"
  done

  # Fake vsh-hosts: `list` answers like vshd, everything else is recorded.
  _stub ssh '
    args="$*"
    host=""; for a in "$@"; do case "$a" in root@*) host=${a#root@};; esac; done
    case "$args" in
      *" list")
        case "$host" in
          vshhost1) printf "%s\n" "vshhost1 web01.vsh.test lxc:web01.vsh.test RUNNING" "vshhost1 db01.vsh.test lxc:db01.vsh.test RUNNING" ;;
          vshhost2) printf "%s\n" "vshhost2 app01.vsh.test lxc:app01.vsh.test STOPPED" "root@vshhost2 gw	ssh:target proxy" ;;
        esac ;;
      *) echo "ssh $args" >> "$VSH_TEST_CALLS"; echo "remote($host): ${args#*$host }"; exit "$VSH_TEST_EXIT" ;;
    esac'
  _stub ssh-add 'case "$1" in -l) exit 1;; -L) exit 0;; *) exit 0;; esac'
  # DNS knows the vsh-hosts, nothing else.
  _stub host '
    case "$1" in
      vshhost1|vshhost2) echo "$1.vsh.test has address 192.0.2.1" ;;
      *) echo "Host $1 not found: 3(NXDOMAIN)"; exit 1 ;;
    esac'

  export PATH="$CLIENT_BIN:$STUBS:$PATH"
}

ssh_calls() { cat "$CALLS"; }
