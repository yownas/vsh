#!/usr/bin/env bats
# contrib/vsh-agent: ssh-agent with VSH_* instead of SSH_* variables.
#
# ssh-agent is a stub that prints what a real one prints.

load helpers

setup() {
  STUBS=$BATS_TEST_TMPDIR/stubs
  mkdir -p "$STUBS"
  export PATH="$STUBS:$PATH"
  # Package layout has bin/, the source tree has contrib/.
  agent=$VSH_SRC/bin/vsh-agent
  [ -e "$agent" ] || agent=$VSH_SRC/contrib/vsh-agent
}

@test "start renames the variables but not the socket path" {
  # The random part of the socket path can contain "SSH".
  _stub ssh-agent '
    echo "SSH_AUTH_SOCK=/tmp/ssh-XSSHx/agent.42; export SSH_AUTH_SOCK;"
    echo "SSH_AGENT_PID=42; export SSH_AGENT_PID;"
    echo "echo Agent pid 42;"'
  run sh "$agent"
  [ "$status" -eq 0 ]
  [ "$output" = $'VSH_AUTH_SOCK=/tmp/ssh-XSSHx/agent.42; export VSH_AUTH_SOCK;\nVSH_AGENT_PID=42; export VSH_AGENT_PID;\necho Agent pid 42;' ]
}
