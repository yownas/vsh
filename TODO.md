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

- `vsh_getctname` parses `host` output with `tail -1`; it relies on AAAA/MX
  lookups for an A-only name returning NODATA. A resolver that answers
  NXDOMAIN there (dnsmasq `address=`) breaks name lookups.
- `egrep` prints "egrep is obsolescent" warnings on GNU grep >= 3.8, which
  reach the client's stderr.
- `libexec/vshd-FreeBSD` is only placeholders: every function prints
  "NOT IMPLEMENTED ON HOST" and `vsh_cttoname` is missing, so `run` on a
  FreeBSD vsh-host fails with "command not found". Only the vshd core
  (permissions, hostrun, `ssh:` proxies) works there.
- `libexec/vshd-SunOS` uses `tail +2`, which GNU tail rejects, and vshd's
  permission checks need `ENVIRON` in awk, which the traditional Solaris
  `/usr/bin/awk` may not have. Neither shows up with stubbed backends.
- shellcheck cannot parse `vsh` line 16 (`[ \! ... ]`) or `modules/qc` and
  skips most of those files, so the lint report understates them.
- doc/TROUBLESHOOTING: OpenSSH >= 9.8 `PerSourcePenalties` locks a
  workstation out for a while after failed logins (e.g. trying vsh before
  the key is installed).

## Test suite backlog

Coverage today: vshd permission checks, request parsing, logging, LXC and
`ssh:` proxy `run`, and the client's run/list/hostrun/`-k`/`-o` paths are
well covered in both tiers. The gaps are the non-LXC backends, the less
used client options, and everything in `modules/` and `contrib/`.

### Small (unit tier, existing helpers)

- `contrib/vsh-complete.bash`: source it with a ctstate file, set
  `COMP_WORDS`/`COMP_CWORD`, call `_vsh` and check `COMPREPLY`.
- vshd denials for `move-offline`, `moveall` and `moveall-offline`; each is
  its own branch with its own error message.
- Client requests for `-o moveall`, `-o moveall-offline` and
  `-o move-offline`.
- Proxy clients: a `user@host` entry (`gw3 ssh:deploy@target` runs
  `ssh deploy@target`) and a `runas` user on a proxy alias
  (`ssh app@target`).
- `vsh -d` with `VSH_DISTKEYFOLDER`, and `VSH_HOSTFILE` selecting which
  hosts get `list`.
- `vsh -g <role>` writes `user=<me>+<role>` into the dist key (stub
  `ssh-keygen` to avoid the passphrase prompt).
- `[hosts]` and `[modules]` entries naming a single host or module, not
  only `*`.
- `modules/wol`: stub `socat`, check the magic packet (`FF`x6 + MAC x16),
  the host pattern and that malformed MACs are skipped.
- `contrib/vshcopy`: stub `vsh`, check the `cd <dir> && tar` commands for
  local to remote, remote to local and remote to remote.
- vshd `list` with `vsh:` entries in proxy-clients (reuse the stub `vsh`
  from the KB-4 test).

### Backends

- OpenVZ backend: a Nix-packaged `vzlist`/`vzctl`/`vzmigrate` shim with
  per-CT state and argv logging, to cover `move` (live/offline), the
  `moveall` round-robin over hosts, running as a non-root `runas` user
  (`su -`, including the `\'"$tmp_ccmd"\'` quoting) and the `qc` module
  (`modules/qc`, `modulesd/qc`). A plain argv-recording stub in the unit
  tier gets most of this before the full shim exists.
- Virtuozzo backend: `prlctl` personality of the same shim.
- SunOS and FreeBSD backends (`libexec/vshd-SunOS`, `vshd-FreeBSD`). vshd
  picks the backend with `$(uname)` from `PATH`, so a `uname` stub plus
  `zoneadm`/`zlogin` (or jail) stubs can run the existing unit tests
  against each backend; `setup_vshd` then needs to copy all of `libexec/`.
  This tests the backend logic with GNU tools only.
- SunOS and FreeBSD in real VMs, to catch the native awk/sed/grep/tail
  differences and drive real zones/jails. On GitHub, `vmactions/freebsd-vm`
  and `vmactions/omnios-vm` (or `openindiana-vm`, `solaris-vm`) boot QEMU
  VMs on `ubuntu-latest` with KVM, as the integration job does. Boot takes
  minutes, so run them on a schedule, `workflow_dispatch` and PRs touching
  `vshd` or `libexec/`.
  - The VM is throwaway, so run the unit tier with vshd directly as root
    instead of in bwrap (no bwrap on FreeBSD/illumos). This is the same
    bwrap-free `vshd_as` mode the packaged-distro job below needs.
  - FreeBSD: only the vshd core until `vshd-FreeBSD` has a jail backend.
  - OmniOS: the vshd core plus one real zone for `list`/`run`/`start`/`stop`.
  - Locally: fetch FreeBSD's `BASIC-CI` image with a pinned hash in the
    flake and boot it with a small QEMU wrapper (`vsh-test freebsd`) over
    ssh; the NixOS test driver cannot drive non-NixOS guests. OmniOS
    publishes cloud images with a `.sha256` for stable and LTS
    (`downloads.omnios.org/media/stable/omnios-r151058.cloud.qcow2`, also
    raw.zst/vmdk), so the same works for it; how that image takes an ssh
    key at first boot is undocumented, so check that first.
    `vmactions/omnios-vm` instead boots its own qcow2 built by
    `anyvm-org/omnios-builder` (installer ISO, SSH enabled), and supports
    r151046 to r151058 including the LTS releases.
  - OmniOS also publishes a non-global zone image (`*.ngz.zfs.xz`), which
    should let the test zone be installed without reaching the package
    repository.

### Integration

- `vsh -x` (X11 forwarding) and `contrib/vcp` / `vshcopy`, which need sshd
  inside the container rootfs.
- `vsh:` proxy (vshd using vsh to reach other hosts) end to end.
- Onboarding a role key: `vsh -g admin`, install the dist key, use it as
  `alice+admin`.

### Tooling and CI

- Measure line coverage with kcov (bash tracing under bats), starting with
  the client and contrib tests that run outside bwrap.
- Run the unit tier against the installed packages on every distro in the
  `packages` workflow's install job (EL8/9/10, Fedora, Debian, Ubuntu,
  Alpine), replacing `packaging/smoke-test`. The bwrap-free `vshd_as` mode
  is shared with the SunOS/FreeBSD VM jobs, so do this first:
  - `vshd_as` mounts only `/nix` in bwrap and limits `PATH` to store paths;
    without `/nix`, mount `/usr` (and `/bin`, `/lib`, `/sbin` where they are
    real directories, as on Alpine) and use the system `PATH`.
  - Point `VSH_PKG` at the installed files (`/opt/vsh/bin/vshd`,
    `/opt/vsh/libexec`, `/opt/vsh/modulesd`, `/usr/bin/vsh`).
  - Run the containers with `--privileged`, since Docker's seccomp profile
    blocks the namespaces bwrap needs.
  - Install bats-core from a pinned release (Ubuntu 22.04 has 1.2, EL only
    has it in EPEL) and bubblewrap from the distro.
  - Expect differences from busybox (Alpine) and GNU grep's egrep warning;
    each is either a portability bug or a test that assumes GNU tools.
- Make the lint job blocking once the shellcheck backlog is triaged.
