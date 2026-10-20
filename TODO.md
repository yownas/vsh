# TODO

## Known bugs

Each `KB-n` is pinned by an `expect_known_bug` marker in the tests: the test
asserts the *correct* behaviour and passes while the bug exists. When a fix
lands that test fails with "KB-n appears to be FIXED"; turn the marker into
a plain assertion and remove the entry here. `tests/vsh-test known-bugs`
lists where each one is tested.

### KB-1: client-supplied names are used as regexes in permission checks

`vsh_checkperm` (and `vsh_runas`) build `egrep "^$tmp_item:"` from the
container name the client sent, and the proxy-clients lookup in `vshd` does
the same with awk. A user allowed on one container can pass the check for
another name by sending a regex, e.g. bob (allowed on `db01.vsh.test` only):

    run lxc:web01.vsh.test|db01.vsh.test true    # allowed, logged as "run bob ..."
    run lxc:.* true                              # allowed (with no dotfiles in cwd)

The backend call that follows currently fails because the name is not a real
container, but the authorization decision itself is wrong. With `.*` the
proxy-clients lookup also matches every entry.

### KB-2: globs in a request expand on the vsh-host

`vsh_parse $ORIGINAL_COMMAND` and later `$tmp_ccmd` are unquoted, so
`vsh web01 ls /etc/*.conf` lists the *host's* files. The result also depends
on the files in vshd's working directory (root's home), which changes how
KB-1 behaves.

### KB-3: module names can leave modulesd

`module ../../../../../../../../etc/hostname` sources a file outside
`/opt/vsh/modulesd`. With `[modules] *:...` any permitted user can source any
file on the host as root.

### KB-4: `vsh:` proxy targets are checked against the id, not the name

In `libexec/vshd-Linux` `vsh_cttoname` the `vsh)` branch prints the name to
stdout instead of setting `vsh_return`, so the permission check uses the id
and the name leaks into the output.

### KB-5: remote exit status is lost

Both `vshd` (ends with `LOG`) and `vsh` (ends with the agent cleanup) exit 0
whatever the command in the container returned: `vsh web01 false` exits 0.

### KB-6: moving an LXC container by name silently does nothing

The client sends `move <name> <host>`. `vsh_movect` only refuses `lxc:*`
paths, then finds neither `prlctl` nor `vzmigrate` and returns 0 without a
message.

### KB-7: names unknown to DNS fail until the statefile is refreshed

`vsh` resolves the target (`vsh_getctname`) before the action refreshes the
statefile, so on a new workstation (or for a new container) `vsh gw` fails
with "Can not find container" until `vsh -l` has been run.

### KB-8: `vsh -t` cannot record host keys when ~/.ssh does not exist

The second `vsh -t` runs `mv ~/.ssh/known_hosts ...` and writes the new
file without creating `~/.ssh`, so on a fresh account no host keys are saved.

## Other findings

- `vsh`: `ps ... | grep " $VHS_AGENT_PID "` — typo for `VSH_AGENT_PID`, so
  any running ssh-agent of the user counts as the vsh-agent.
- `vsh_getctname` parses `host` output with `tail -1`; it relies on AAAA/MX
  lookups for an A-only name returning NODATA. A resolver that answers
  NXDOMAIN there (dnsmasq `address=`) breaks name lookups.
- `egrep` prints "egrep is obsolescent" warnings on GNU grep >= 3.8, which
  reach the client's stderr.
- shellcheck cannot parse `vsh` line 16 (`[ \! ... ]`) or `modules/qc` and
  skips most of those files, so the lint report understates them.
- doc/TROUBLESHOOTING: OpenSSH >= 9.8 `PerSourcePenalties` locks a
  workstation out for a while after failed logins (e.g. trying vsh before
  the key is installed).

## Test suite backlog

- OpenVZ backend: a Nix-packaged `vzlist`/`vzctl`/`vzmigrate` shim with
  per-CT state and argv logging, to cover `move` (live/offline), running as
  a non-root `runas` user (`su -`) and the `qc` module.
- Virtuozzo backend: `prlctl` personality of the same shim.
- SunOS and FreeBSD backends (`libexec/vshd-SunOS`, `vshd-FreeBSD`).
- `vsh -x` (X11 forwarding) and `contrib/vcp` / `vshcopy`, which need sshd
  inside the container rootfs.
- `vsh:` proxy (vshd using vsh to reach other hosts) end to end.
- `contrib/vsh-complete.bash`.
- Make the lint job blocking once the shellcheck backlog is triaged.
