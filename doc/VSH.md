# Client reference: `vsh`

```
vsh [options] [action]
```

Running `vsh` with no arguments, or with an unknown flag (or `-?`), prints the
built-in usage.

**Options must come before the action.** Parsing stops at the first action
(a container name, `-r`, `-x`, `-h`, `-H`, `-o`, `-M`, ...), and everything
after it belongs to that action. `vsh -u web01` uses the cache, but
`vsh web01 -u` runs the command `-u` in web01. `-l` is the exception: options
after it are still read, but `-u` only skips loading keys when it comes
first (`vsh -u -l`).

## Options

| Option | Effect |
| --- | --- |
| `-k <suffix>` | Use the key/role `<suffix>`, i.e. `~/.vsh/keys/vsh-<login>-<suffix>`. Default is `user`, or `$VSH_KEY`. With no suffix, list your keys. |
| `-a` | Add the selected key to your running ssh-agent for `$VSH_KEYLIFE` seconds (default 9 h) so you are not asked for the passphrase again. Implies `-q`. |
| `-u` | Do not refresh the container state from all hosts; use the cached statefile. Same as `VSH_UPDATE=0`. |
| `-p` | Prefix every output line with the host/client name. Used with `-o athosts` and `-o atct`. |
| `-q` | Quieter output. Used by `-g`, and suppresses the usage text. |

## Actions

### Run in a container

```
vsh [-r] <container> [<command...>]
```

Opens a root shell in `<container>`, or runs `<command>` there. `-r` is
optional. `<container>` can be anything that appears in `vsh -l`: an
OpenVZ hostname or CTID, an LXC name, a zone name, or a proxy alias. A name
that is not in the statefile is looked up in DNS.

If `<container>` is one of the vsh-hosts in your hostfile, this becomes a
`hostrun` on that host (see `-H`).

You get a TTY only when no command is given. To run an interactive
full-screen program (`top`, `vi`, `screen`), use `-x` or start a shell
first.

```sh
vsh web01                         # shell
vsh web01 uptime                  # command
vsh web01 'tail -n 50 /var/log/messages | grep error'   # quote shell syntax
```

Commands are passed through several shells, so quote anything that
contains `|`, `;` or `>`. Note that LXC containers execute the command
directly with no shell around it. Use `vsh ct "sh -c '...'"` there when you
need pipes.

**Globs expand on the vsh-host.** `vshd` word-splits the request without
quoting it, so `*`, `?` and `[...]` are matched against files on the
vsh-host (in the home directory of the user `vshd` runs as) before the
command reaches the container. Quoting on your side does not prevent this:
`vsh web01 'ls /etc/*.conf'` lists the matches from the *host's* `/etc`
whenever there are any. Avoid globs in commands, or put the command in a
script inside the container.

### Run with X11 forwarding and a real TTY

```
vsh -x <container> [<command...>]
```

`-x` starts a throw-away `sshd -i` inside the container through the vsh
channel and connects to it with `ssh -XY`, using your X11 key. That gives
you X11 forwarding and full TTY allocation. You need:

* `~/.vsh/keys/vsh-<login>-X11`. `vsh -t` creates it, or run `vsh -g X11`.
  This key never needs distributing.
* `/usr/sbin/sshd` and `xauth` inside the container.

The temporary host key and authorized key are written to `~/.vsh/` of the
remote user inside the container and deleted when the session ends.

`vsh -x` is also the entry point when `scp` uses vsh as its transport.
See [CONTRIB.md → vcp](CONTRIB.md#vcp-scp-over-vsh).

### Run on the vsh-host

```
vsh -H                       # list hosts from the hostfile
vsh -H <host> [<command>]    # shell/command on that vsh-host
vsh -h <container> [<command>]   # shell/command on the host *running* <container>
```

This needs the `[hosts]` permission in `vshd.ini`. A shell is started as
`/bin/bash -il`, and a command is run with `eval`.

### List containers

```
vsh -l      # names
vsh -ll     # name@host
vsh -lll    # host, name, id/path, status (the raw statefile)
```

`vsh -u -l` lists from the cache without contacting any host and without
loading keys. This is useful offline or for shell completion.

### Operations: `-o`

| Command | Effect | `vshd.ini` permission |
| --- | --- | --- |
| `-o start <ct>` | Start a container | `[operations] startstop` |
| `-o stop <ct>` | Stop a container | `[operations] startstop` |
| `-o move <ct> <host>` | Migrate, live if the container is running | `[operations] move` |
| `-o move-offline <ct> <host>` | Migrate offline (stop, move, start) | `[operations] move` |
| `-o moveall <src> <dst1> [<dst2>...]` | Migrate every container on `<src>`, spread round-robin over the destinations | `[operations] move` |
| `-o moveall-offline <src> <dst1> [...]` | Same, offline | `[operations] move` |
| `-o athosts <command>` | Run `<command>` on **every** vsh-host in the hostfile, one after another | `[hosts]` |
| `-o atct <command> < list` | Run `<command>` in every container named on stdin (one per line) | `[containers]` per target |

Migration works only with OpenVZ (`vzmigrate`) and Virtuozzo (`prlctl
migrate`). See [VSHD.md → Backends](VSHD.md#platform-backends) for what is
needed between hosts.

`atct` handles targets one at a time. A target you lack permission for
prints `permission denied` and the run continues. A name that is not in the
statefile or DNS, or that no vsh-host lists, **aborts the whole run**
without `-p`. With `-p` the error is printed (prefixed like any other
output) and the run continues. Check the list against `vsh -l` first. For long runs, load your key with `-a`
first (see [ssh-agent handling](#ssh-agent-handling)).

```sh
vsh -p -o athosts 'df -h /'
vsh -l | grep '^web' > web.txt
vsh -u -p -o atct 'yum -q check-update' < web.txt
vsh -k admin -o moveall vsh-host1 vsh-host2 vsh-host3   # empty host1 for maintenance
```

Avoid piping one `vsh` straight into another (`vsh -l | vsh -o atct ...`)
unless the second one has `-u`. Both would refresh the statefile at the
same time and can corrupt each other's results.

### Modules: `-M`

```
vsh -M <module> [<args...>]
vsh -M list [-l]
```

Sources `~/.vsh/modules/<module>` inside the running `vsh`. See
[MODULES.md](MODULES.md).

### Key management

| Command | Effect |
| --- | --- |
| `vsh -t` | First run: create `~/.vsh/{hosts,var,keys}` and generate the `X11` and `user` keys. Later runs: add the SSH host keys of all hostfile entries to `~/.ssh/known_hosts`. |
| `vsh -g [<suffix>]` | Generate key pair `vsh-<login>-<suffix>` (default `user`) and its `.dist.pub`. If the key exists, print its `.dist.pub` and exit 1. The user name in `.dist.pub` is `<login>` for `user` and `<login>+<suffix>` otherwise. `X11` keys get no passphrase and no `.dist.pub`. |
| `vsh -k` | List your keys (suffixes of all `.dist.pub` files). |
| `vsh -k <suffix> <action>` | Use another role for this one command. |
| `vsh -d` | Copy all your `.dist.pub` files to `$VSH_DISTKEYFOLDER` (default `/tmp/<login>/`). |

Keys are RSA keys created with `ssh-keygen -t rsa`.

## ssh-agent handling

`vsh` uses an agent so it only asks for your passphrase when necessary:

1. If `VSH_AUTH_SOCK` is set, it is used as `SSH_AUTH_SOCK`. This keeps vsh
   keys apart from your normal agent (see
   [CONTRIB.md → vsh-agent](CONTRIB.md#vsh-agent)).
2. If no agent can be reached, `vsh` looks for
   `~/.vsh/var/<fqdn>.agent`. That file holds the environment of a
   `vsh-agent` started earlier. If that agent can still be reached it is
   reused; if not (no file, or the agent died, e.g. after a reboot), a new
   `vsh-agent` is started and saved there. This requires `vsh-agent` in
   `$PATH`. `vsh` runs started at the same time share one new agent
   (`<fqdn>.agent.lock` is held while it starts).
3. If there is still no agent, a temporary `ssh-agent` is started and
   killed again when `vsh` exits.
4. With `-a`, the key is added for `$VSH_KEYLIFE` seconds.
5. If the key is not loaded yet, it is added with a **30-second** lifetime
   and removed again when `vsh` exits. Long runs (`-o atct`,
   `-o athosts`, `-M qc` over many targets) can outlast those 30 seconds
   and then ask for the passphrase again halfway through. Load the key with
   `-a` first.

A key counts as loaded when its fingerprint is in the agent, whatever its
comment. Load it once in the morning:

```sh
eval $(ssh-agent)       # if you don't have one already
vsh -a -l               # asks for the passphrase once, valid for 9 hours
```

Avoid gpg-agent's ssh support for vsh keys. gpg-agent stores added keys
on disk (`~/.gnupg/private-keys-v1.d/` and `sshcontrol`), and `ssh-add -d`
reports success without removing them, so the 30-second keys pile up. Use
`ssh-agent` or `vsh-agent` instead.

## Environment variables

| Variable | Default | Effect |
| --- | --- | --- |
| `VSH_HOSTFILE` | `~/.vsh/hosts` | Hostfile to use. Point several admins at a shared file. |
| `VSH_KEY` | `user` | Default key suffix (role). `-k` overrides it. Handy with `scp -S vsh`, which cannot pass `-k` (rsync can: `rsync -e 'vsh -k admin'`). |
| `VSH_UPDATE` | *(update)* | `0` or `false` works like `-u` for every call. |
| `VSH_KEYLIFE` | `32400` (9 h) | Lifetime in seconds for keys added with `-a`. |
| `VSH_AUTH_SOCK` | *(unset)* | Agent socket to use instead of `SSH_AUTH_SOCK`. |
| `VSH_DISTKEYFOLDER` | `/tmp/<login>/` | Destination for `vsh -d`. |

## Files

| Path | Purpose |
| --- | --- |
| `~/.vsh/hosts` | Hostfile: one vsh-host per line, `[user@]host`. Only the first word counts, lines starting with `#` are skipped. |
| `~/.vsh/keys/vsh-<login>-<suffix>[.pub,.dist.pub]` | Keys, see above. |
| `~/.vsh/var/ctstate` | Statefile: `host name id/path status`, rebuilt on each update. |
| `~/.vsh/var/ctstate_<host>` | Per-host partial results while updating. |
| `~/.vsh/var/<fqdn>.agent` | Saved `vsh-agent` environment. |
| `~/.vsh/modules/` | Client-side modules for `-M`. |

## Fixed SSH behaviour

Every connection uses
`ssh -o PasswordAuthentication=no -o NumberOfPasswordPrompts=0 -o ConnectTimeout=4 -i <key>`.
A host that does not answer within 4 seconds is skipped during state
updates. Other per-host SSH settings, such as `Port` or `ProxyJump`, can
go in `~/.ssh/config` under the host name from your hostfile. `ssh` picks
them up as usual. `User` cannot be set there, because vsh always passes an
explicit user (`root@`, or the one from the hostfile).

`vsh -t` collects host keys with `ssh-keyscan`, which reads neither
`~/.ssh/config` nor the `user@` prefix. For hosts on a non-standard port,
behind a `ProxyJump`, or written as `user@host` in the hostfile, it fails
silently. Accept their host keys once by hand instead, e.g.
`ssh -i ~/.vsh/keys/vsh-$USER-user proxyuser@jump.example.com list`.
