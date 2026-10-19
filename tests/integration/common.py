# Helpers shared by the integration test scripts. Concatenated in front of
# each test script by the Nix test definition, so the driver globals (ws,
# vshhost1, subtest, ...) are in scope.

import re
import shlex


class Expectation(Exception):
    """A check of vsh behaviour failed (as opposed to the test harness)."""


def check(cond, msg):
    if not cond:
        raise Expectation(msg)


def expect_known_bug(kb, fn):
    """fn() asserts the *correct* behaviour using check().

    While the bug exists fn raises Expectation and the test passes. When the
    bug is fixed fn succeeds and this fails, so the marker gets turned into a
    plain assertion and TODO.md is updated. Any other exception (harness
    failure) propagates instead of being mistaken for the bug.
    """
    try:
        fn()
    except Expectation as e:
        print(f"{kb} still present: {e}")
        return
    raise Exception(f"{kb} appears to be FIXED: replace expect_known_bug with a plain assertion and update TODO.md")


def run_as(user, cmd, node=None):
    """Run cmd as user on the workstation. Returns (status, stdout+stderr)."""
    node = node or ws
    return node.execute(f"su - {user} -c {shlex.quote(cmd + ' 2>&1')}")


def vsh(user, args, stdin=None):
    """Run vsh as user, require success, return its stdout.

    stderr is printed to the test log rather than returned, so warnings do
    not break comparisons.
    """
    cmd = f"vsh {args} 2>/tmp/vsh-stderr"
    if stdin is not None:
        cmd = f"printf %s {shlex.quote(stdin)} | {cmd}"
    status, out = ws.execute(f"su - {user} -c {shlex.quote(cmd)}")
    err = ws.succeed("cat /tmp/vsh-stderr; rm -f /tmp/vsh-stderr")
    if err.strip():
        print(f"stderr of `vsh {args}` as {user}:\n{err}")
    if status != 0:
        raise Exception(f"`vsh {args}` as {user} exited {status}:\n{out}{err}")
    return out


def check_out(out, expected, what):
    check(out.strip() == expected, f"{what}: expected {expected!r}, got {out.strip()!r}")


def vshd_raw(user, key, host, request):
    """Send a raw request to vshd with ssh, bypassing the vsh client."""
    return run_as(
        user,
        f"ssh -i ~/.vsh/keys/{key} -o BatchMode=yes -o StrictHostKeyChecking=accept-new root@{host} {shlex.quote(request)}",
    )


def lines(out):
    return [l for l in out.splitlines() if l.strip()]


def assert_logged(node, pattern, priority=None):
    """Assert vshd wrote a syslog line matching the regex pattern."""
    prio = f"-p {priority}..{priority}" if priority else ""
    log = node.succeed(f"journalctl --no-pager -o cat {prio} | grep -F 'vshd (' || true")
    check(
        any(re.search(pattern, l) for l in log.splitlines()),
        f"no vshd log line matching {pattern!r} (priority {priority}) on {node.name}",
    )
