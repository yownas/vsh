# Onboarding: a new admin (carol) goes from nothing to a working vsh with
# passphrase-protected keys, following doc/QUICKSTART.md. Then hardening
# checks that need raw requests to vshd.

start_all()
vshhost1.wait_for_unit("dnsmasq.service")
vshhost1.wait_for_unit("sshd.service")
vshhost1.wait_for_unit("vsh-test-containers.service")
ws.wait_for_unit("multi-user.target")

PASS = "correct horse battery staple"
KEY = "/home/carol/.vsh/keys/vsh-carol-user"


def carol(cmd):
    """Run cmd as carol on a pty, answering passphrase prompts."""
    return ws.execute(f"su - carol -c {shlex.quote(f'{VSH_EXPECT} {shlex.quote(PASS)} {cmd}')} 2>&1")


with subtest("vsh -t on a fresh account creates the hostfile, statedir and keys"):
    status, out = carol("vsh -t")
    check(status == 0, f"vsh -t exited {status}: {out}")
    check("hosts created" in out, f"no 'hosts created' message: {out}")
    ws.succeed("test -f /home/carol/.vsh/hosts -a ! -s /home/carol/.vsh/hosts")
    ws.succeed("test -d /home/carol/.vsh/var")
    ws.succeed(f"test -s {KEY} -a -s {KEY}.pub -a -s {KEY}.dist.pub")
    check(ws.succeed(f"stat -c %a {KEY}").strip() == "600", "private key must be 0600")
    ws.fail(f"ssh-keygen -y -P '' -f {KEY}")  # passphrase protected
    ws.succeed(f"ssh-keygen -y -P {shlex.quote(PASS)} -f {KEY}")
    dist = ws.succeed(f"cat {KEY}.dist.pub").strip()
    check(dist.startswith('command="/opt/vsh/bin/vshd user=carol" ssh-'), f"dist key: {dist}")
    ws.succeed("test -s /home/carol/.vsh/keys/vsh-carol-X11")
    ws.fail("test -e /home/carol/.vsh/keys/vsh-carol-X11.dist.pub")
    ws.fail("ssh-keygen -y -P x -f /home/carol/.vsh/keys/vsh-carol-X11 2>&1 | grep -q incorrect")

def learns_host_keys():
    status, out = carol("vsh -t")
    check("Adding keys to ~/.ssh/known_hosts" in out, f"vsh -t: {out}")
    status, _ = ws.execute("grep -q '^vshhost1 ' /home/carol/.ssh/known_hosts")
    check(status == 0, f"vshhost1 not in known_hosts; vsh -t said: {out}")


with subtest("KB-8: second vsh -t cannot record host keys when ~/.ssh does not exist"):
    ws.succeed("su - carol -c 'echo vshhost1 > ~/.vsh/hosts'")
    expect_known_bug("KB-8", learns_host_keys)

with subtest("second vsh -t learns the host keys of the hostfile"):
    ws.succeed("su - carol -c 'install -d -m700 ~/.ssh'")
    learns_host_keys()

with subtest("before the key is installed, vshhost1 refuses carol"):
    status, out = carol("vsh -l")
    check("web01.vsh.test" not in out, f"carol listed containers without an installed key: {out}")

with subtest("after the admin installs the dist key, carol can work"):
    vshhost1.succeed(f"echo {shlex.quote(dist)} >> /root/.ssh/authorized_keys")
    status, out = carol("vsh -l")
    check("web01.vsh.test" in out and "db01.vsh.test" in out, f"vsh -l: {out}")
    status, out = carol("vsh web01 cat /etc/vsh-ct-name")
    check("web01.vsh.test" in out, f"vsh web01: {out}")
    status, out = carol("vsh db01.vsh.test true")
    check("run permission denied for carol@db01.vsh.test" in out, f"carol on db01: {out}")
    assert_logged(vshhost1, r"ARG: user=carol CMD: run lxc:web01\.vsh\.test cat /etc/vsh-ct-name", "info")
    assert_logged(vshhost1, r"error: run permission denied for carol@db01\.vsh\.test", "err")

# ---------------------------------------------------------------- ssh-agent
#
# carol has no agent of her own, so vsh starts a vsh-agent and saves its
# environment in ~/.vsh/var/<fqdn>.agent.

import time

AGENTFILE = "~/.vsh/var/$(hostname -f).agent"


def in_vsh_agent(cmd):
    """Run cmd as carol against the vsh-agent saved in AGENTFILE."""
    return ws.succeed(f"su - carol -c {shlex.quote(f'. {AGENTFILE}; export SSH_AUTH_SOCK=$VSH_AUTH_SOCK; {cmd}')}")


def agent_reachable():
    # ssh-add -l: 0 = keys, 1 = no keys, 2 = no agent
    return in_vsh_agent("ssh-add -l > /dev/null; echo $?").strip() in ("0", "1")


with subtest("vsh replaces a saved vsh-agent that has died"):
    check(agent_reachable(), "earlier vsh runs left no reachable vsh-agent")
    old = in_vsh_agent("echo $VSH_AGENT_PID").strip()
    # Another ssh-agent of carol's (e.g. her desktop's) must not be mistaken
    # for the dead vsh-agent.
    ws.succeed("su - carol -c 'ssh-agent > /dev/null'")
    ws.succeed(f"kill {old}")
    ws.wait_until_fails(f"kill -0 {old}")
    status, out = carol("vsh web01 cat /etc/vsh-ct-name")
    check(status == 0 and "web01.vsh.test" in out, f"vsh web01 after the agent died: {out}")
    new = in_vsh_agent("echo $VSH_AGENT_PID").strip()
    check(new != old, f"{AGENTFILE} still points at the dead agent {old}")
    check(agent_reachable(), "the new vsh-agent can not be reached")

# Without vsh-agent in $PATH and no agent to reach, vsh starts a temporary
# ssh-agent for the run.
ws.succeed(
    "mkdir -p /tmp/no-vsh-agent && for f in /run/current-system/sw/bin/*; do"
    ' [ "${f##*/}" = vsh-agent ] || ln -sf "$f" /tmp/no-vsh-agent/; done'
)
NO_VSH_AGENT = "PATH=/tmp/no-vsh-agent:/run/wrappers/bin"
# Host keys are not trusted globally on this workstation.
ws.succeed("su - alice -c 'install -d -m700 ~/.ssh && ssh-keyscan vshhost1 > ~/.ssh/known_hosts 2> /dev/null'")


def ssh_agents(user):
    return int(ws.succeed(f"pgrep -c -u {user} -x ssh-agent || true").strip())


with subtest("a vsh run that fails leaves no temporary ssh-agent behind"):
    before = ssh_agents("alice")
    status, out = run_as("alice", f"{NO_VSH_AGENT} vsh nosuch true")
    check(status == 1 and "Can not find container nosuch" in out, f"vsh nosuch: {status} {out}")
    check(ssh_agents("alice") == before, "a temporary ssh-agent is still running")

with subtest("a vsh run that fails removes the temporary key from the user's agent"):
    status, out = run_as(
        "alice", "eval $(ssh-agent) > /dev/null; vsh nosuch true; ssh-add -l; eval $(ssh-agent -k) > /dev/null"
    )
    check("Can not find container nosuch" in out, f"vsh nosuch: {out}")
    check("vsh-alice-user" not in out, f"the temporary key is still in the agent: {out}")


def vsh_killed_by(sig):
    """Kill a running vsh, and its ssh, like a terminal would its job."""
    before = ssh_agents("alice")
    # Own process group, default signal dispositions (a background job of
    # a non-interactive shell would ignore INT).
    ws.succeed(
        f"su - alice -c '{NO_VSH_AGENT} env --default-signal setsid vsh web01.vsh.test sleep 60"
        " > /tmp/vsh-killed.log 2>&1 < /dev/null & echo $! > /tmp/vsh.pid'"
    )
    pid = ws.succeed("cat /tmp/vsh.pid").strip()
    try:
        ws.wait_until_succeeds("pgrep -u alice -f 'run lxc:web01.vsh.test sleep 60'", timeout=30)
    except Exception:
        print(ws.execute("cat /tmp/vsh-killed.log; ps -fu alice")[1])
        raise
    ws.succeed(f"kill -{sig} -- -{pid}")
    ws.wait_until_fails(f"kill -0 {pid}", timeout=30)
    return ssh_agents("alice") - before


for sig in ("HUP", "INT", "TERM"):
    with subtest(f"a vsh killed by SIG{sig} leaves no temporary ssh-agent behind"):
        left = vsh_killed_by(sig)
        check(left == 0, f"{left} temporary ssh-agent(s) still running after SIG{sig}")

# A vsh-agent that takes a second to start, so that concurrent vsh runs all
# find no agent before the first one has saved its environment.
ws.succeed(
    "mkdir -p /tmp/slow-vsh-agent && printf '%s\\n' '#!/bin/sh' '[ -z \"$1\" ] && sleep 1'"
    " 'exec /run/current-system/sw/bin/vsh-agent \"$@\"' > /tmp/slow-vsh-agent/vsh-agent"
    " && chmod +x /tmp/slow-vsh-agent/vsh-agent"
)

with subtest("vsh runs started at the same time share one new vsh-agent"):
    ws.succeed("su - alice -c 'rm -f ~/.vsh/var/*.agent'")
    before = ssh_agents("alice")
    status, out = run_as(
        "alice",
        "export PATH=/tmp/slow-vsh-agent:$PATH; for i in 1 2 3 4 5; do vsh -u web01.vsh.test true & done; wait",
    )
    check("Can not" not in out and "denied" not in out, f"concurrent vsh runs failed: {out}")
    started = ssh_agents("alice") - before
    check(started == 1, f"{started} vsh-agents started by 5 concurrent vsh runs")

with subtest("a lock left by a killed vsh does not block vsh"):
    # As if vsh had been killed with SIGKILL while starting the vsh-agent.
    ws.succeed("su - alice -c 'f=~/.vsh/var/$(hostname -f).agent; rm -f $f; mkdir $f.lock'")
    status, out = run_as("alice", "timeout 60 vsh -u web01.vsh.test echo through")
    check(status == 0 and "through" in out, f"vsh with a stale lock: {status} {out}")

with subtest("a vsh killed while starting the vsh-agent does not make the next one wait"):
    ws.succeed("su - alice -c 'rm -f ~/.vsh/var/*.agent'")
    ws.succeed(
        "su - alice -c 'PATH=/tmp/slow-vsh-agent:$PATH env --default-signal setsid vsh -u web01.vsh.test true"
        " > /dev/null 2>&1 < /dev/null & echo $! > /tmp/vsh.pid'"
    )
    pid = ws.succeed("cat /tmp/vsh.pid").strip()
    ws.wait_until_succeeds("pgrep -u alice -f slow-vsh-agent", timeout=30)
    ws.succeed(f"kill -TERM -- -{pid}")
    ws.wait_until_fails(f"kill -0 {pid}", timeout=30)
    t0 = time.monotonic()
    status, out = run_as("alice", "vsh -u web01.vsh.test echo through")
    elapsed = time.monotonic() - t0
    check(status == 0 and "through" in out, f"next vsh: {status} {out}")
    check(elapsed < 5, f"next vsh waited {elapsed:.0f}s for the lock of the killed one")

# ---------------------------------------------------------------- hardening

with subtest("non-printable characters in a request are rejected and logged"):
    status, out = run_as(
        "alice",
        "ssh -i ~/.vsh/keys/vsh-alice-user -o BatchMode=yes -o StrictHostKeyChecking=accept-new "
        "root@vshhost1 \"$(printf 'run lxc:web01.vsh.test echo \\001pwned')\"",
    )
    check("INVALID INPUT" in out and "pwned\n" not in out.replace("#pwned", ""), f"non-printable: {out}")
    assert_logged(vshhost1, r"CMD: usage INVALID INPUT: run lxc:web01\.vsh\.test echo #pwned", "info")


def glob_expands_in_container():
    vshhost1.succeed("touch /root/ONLY-ON-HOST")
    status, out = vshd_raw("alice", "vsh-alice-user", "vshhost1", "run lxc:web01.vsh.test echo /root/*")
    check("ONLY-ON-HOST" not in out, f"glob was expanded on the vsh-host: {out}")


with subtest("KB-2: globs in a request expand on the vsh-host"):
    expect_known_bug("KB-2", glob_expands_in_container)
