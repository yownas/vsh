# Core scenarios: one workstation, two LXC vsh-hosts, one proxied SSH host.
#
#   ws ──▶ vshhost1  web01.vsh.test, db01.vsh.test (LXC), dnsmasq
#   ws ──▶ vshhost2  app01.vsh.test (LXC), proxy clients gw, gw2 ──▶ target

start_all()
vshhost1.wait_for_unit("dnsmasq.service")
for h in (vshhost1, vshhost2, target):
    h.wait_for_unit("sshd.service")
for h in (vshhost1, vshhost2):
    h.wait_for_unit("vsh-test-containers.service")
ws.wait_for_unit("multi-user.target")

ALL = {"web01.vsh.test", "db01.vsh.test", "app01.vsh.test", "gw", "gw2"}

# ---------------------------------------------------------------- discovery

with subtest("list: containers and proxy clients from all hosts"):
    check(set(lines(vsh("alice", "-l"))) == ALL, "vsh -l does not list exactly the expected containers")
    ll = vsh("alice", "-ll")
    for item in ("web01.vsh.test@vshhost1", "db01.vsh.test@vshhost1", "app01.vsh.test@vshhost2", "gw@vshhost2"):
        check(item in ll, f"{item} missing from vsh -ll")
    check(re.search(r"vshhost1 +web01.vsh.test +lxc:web01.vsh.test RUNNING", vsh("alice", "-lll")), "vsh -lll format")
    state = ws.succeed("cat /home/alice/.vsh/var/ctstate")
    check("vshhost2 gw ssh:target proxy" in state, "proxy client missing from statefile")

with subtest("name resolution: statefile, FQDN and short name via DNS"):
    check_out(vsh("alice", "web01.vsh.test cat /etc/vsh-ct-name"), "web01.vsh.test", "by FQDN")
    check_out(vsh("alice", "web01 cat /etc/vsh-ct-name"), "web01.vsh.test", "by short name")
    status, out = run_as("alice", "vsh nosuch true")
    check(status != 0 and "Can not find container nosuch" in out, f"unknown container: {out}")

def first_use_without_statefile():
    ws.succeed("rm -f /home/alice/.vsh/var/ctstate")
    status, out = run_as("alice", "vsh gw hostname")
    check(status == 0 and out.strip() == "target", f"vsh gw on a fresh statefile: {out}")

with subtest("KB-7: names unknown to DNS fail until the statefile is refreshed"):
    expect_known_bug("KB-7", first_use_without_statefile)
    vsh("alice", "-l")

# ---------------------------------------------------------------- run

with subtest("run: command executes inside the LXC container"):
    check_out(vsh("alice", "db01.vsh.test cat /etc/vsh-ct-name"), "db01.vsh.test", "db01")
    check_out(vsh("alice", "app01.vsh.test hostname"), "app01.vsh.test", "app01 on vshhost2")
    assert_logged(vshhost1, r"run alice db01\.vsh\.test \(db01\.vsh\.test\)$", "info")

with subtest("run: interactive shell gets a tty inside the container"):
    ws.succeed(f"su - alice -c '{EXPECT_SHELL} web01.vsh.test'")

with subtest("run: stdin is passed through"):
    check_out(vsh("alice", "web01.vsh.test cat", stdin="through the pipe"), "through the pipe", "stdin")

def exit_status_propagates():
    status, out = run_as("alice", "vsh web01.vsh.test false")
    check(status != 0, "vsh web01 false exited 0")

with subtest("KB-5: remote exit status is lost"):
    expect_known_bug("KB-5", exit_status_propagates)

with subtest("run: per-user permissions"):
    check_out(vsh("bob", "db01.vsh.test cat /etc/vsh-ct-name"), "db01.vsh.test", "bob on db01")
    status, out = run_as("bob", "vsh web01.vsh.test true")
    check("run permission denied for bob@web01.vsh.test" in out, f"bob on web01: {out}")
    assert_logged(vshhost1, r"error: run permission denied for bob@web01\.vsh\.test", "err")

def regex_container_denied():
    # No glob characters: on a real host '.*' is glob-expanded against
    # /root's dotfiles first (KB-2), which hides this bug.
    status, out = vshd_raw("bob", "vsh-bob-user", "vshhost1", "run lxc:web01.vsh.test|db01.vsh.test true")
    check("permission denied" in out, f"bob's regex request was not denied: {out}")

with subtest("KB-1: client-supplied container name is a regex in the permission check"):
    expect_known_bug("KB-1", regex_container_denied)

with subtest("run: proxy clients over ssh, standard and non-standard port"):
    check_out(vsh("alice", "gw hostname"), "target", "gw")
    check_out(vsh("alice", "gw2 printenv VSH_TEST_PORT"), "2222", "gw2 must use port 2222")
    check_out(vsh("bob", "gw2 hostname"), "target", "bob may use gw2")
    status, out = run_as("bob", "vsh gw hostname")
    check("run permission denied for bob@gw" in out, f"bob on gw: {out}")

# ---------------------------------------------------------------- hosts

with subtest("hostrun: -H, -h, and a vsh-host name"):
    check_out(vsh("alice", "-H vshhost1 hostname"), "vshhost1", "-H")
    check_out(vsh("alice", "-h app01.vsh.test hostname"), "vshhost2", "-h")
    check_out(vsh("alice", "vshhost2 hostname"), "vshhost2", "host name as target")
    status, out = run_as("bob", "vsh -H vshhost1 id")
    check("hostrun permission denied for bob@vshhost1" in out, f"bob hostrun: {out}")
    assert_logged(vshhost1, r"hostrun for alice@vshhost1", "info")

with subtest("athosts and atct"):
    out = lines(vsh("alice", "-p -o athosts hostname"))
    check(sorted(out) == ["vshhost1 vshhost1", "vshhost2 vshhost2"], f"athosts: {out}")
    out = lines(vsh("alice", "-p -o atct cat /etc/vsh-ct-name", stdin="web01.vsh.test\napp01.vsh.test\n"))
    check(sorted(out) == ["app01.vsh.test app01.vsh.test", "web01.vsh.test web01.vsh.test"], f"atct: {out}")

# ---------------------------------------------------------------- operations

def ct_state(ct):
    return vshhost2.succeed(f"lxc-info -n {ct} -s").split()[-1]

with subtest("start/stop need the admin role"):
    status, out = run_as("alice", "vsh -o stop app01.vsh.test")
    check("stop app01.vsh.test denied for alice" in out, f"alice stop: {out}")
    check(ct_state("app01.vsh.test") == "RUNNING", "app01 must still run")

    vsh("alice", "-k admin -o stop app01.vsh.test")
    vshhost2.wait_until_succeeds("lxc-info -n app01.vsh.test -s | grep -q STOPPED", timeout=30)
    check(re.search(r"app01\.vsh\.test +lxc:app01\.vsh\.test STOPPED", vsh("alice", "-lll")), "list shows STOPPED")
    assert_logged(vshhost2, r"stop app01\.vsh\.test by alice\+admin", "info")

    vsh("alice", "-k admin -o start app01.vsh.test")
    vshhost2.wait_until_succeeds("lxc-info -n app01.vsh.test -s | grep -q RUNNING", timeout=30)

with subtest("move is permission checked"):
    status, out = run_as("alice", "vsh -o move app01.vsh.test vshhost1")
    check("move-live denied for alice" in out, f"alice move: {out}")

def move_reports_unsupported():
    status, out = run_as("alice", "vsh -k admin -o move app01.vsh.test vshhost1")
    check(status != 0 or "not implemented" in out, f"move of an LXC container gave no error: {out!r}")

with subtest("KB-6: moving an LXC container by name silently does nothing"):
    expect_known_bug("KB-6", move_reports_unsupported)
    check(ct_state("app01.vsh.test") == "RUNNING", "app01 untouched")

# ---------------------------------------------------------------- modules

with subtest("client modules"):
    check("==== list ====" in vsh("alice", "-M list"), "vsh -M list")

def module_confined():
    status, out = vshd_raw("alice", "vsh-alice-user", "vshhost1", "module ../../../../../../../../etc/hostname")
    check("vshhost1: command not found" not in out, f"module outside modulesd was sourced: {out}")

with subtest("KB-3: module names can leave modulesd"):
    expect_known_bug("KB-3", module_confined)

# ---------------------------------------------------------------- audit

with subtest("audit: request, decision and end of session are logged"):
    assert_logged(vshhost1, r"ARG: user=alice CMD: run lxc:web01\.vsh\.test cat /etc/vsh-ct-name", "info")
    assert_logged(vshhost1, r"ARG: user=bob CMD: run lxc:web01\.vsh\.test true", "info")
    assert_logged(vshhost1, r"end session: bob$", "info")
    assert_logged(vshhost2, r"ARG: user=alice\+admin CMD: stop app01\.vsh\.test", "info")
    assert_logged(vshhost2, r"run alice gw2 \(target:2222\)", "info")

# ---------------------------------------------------------------- host down (last: it stops vshhost2)

with subtest("a vsh-host that is down"):
    vsh("alice", "-l")
    vshhost2.crash()
    check("app01.vsh.test" in lines(vsh("alice", "-u -l")), "-u must use the cached statefile")
    ws.succeed("su - alice -c 'VSH_UPDATE=0 vsh -l' | grep -qx app01.vsh.test")

    t0 = ws.succeed("date +%s")
    out = set(lines(vsh("alice", "-l")))
    elapsed = int(ws.succeed("date +%s")) - int(t0)
    check(out == {"web01.vsh.test", "db01.vsh.test"}, f"only vshhost1 containers expected, got {out}")
    check(elapsed < 20, f"vsh -l took {elapsed}s with a host down")
    check_out(vsh("alice", "web01.vsh.test cat /etc/vsh-ct-name"), "web01.vsh.test", "vshhost1 still usable")
