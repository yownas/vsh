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
