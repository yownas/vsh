# Installation

For the short version, see [QUICKSTART.md](QUICKSTART.md). This page covers
each step in detail, plus the options. All examples use the default paths:
the client keeps everything in `~/.vsh/` and the server lives in `/opt/vsh/`.

## Requirements

| Where | Needs |
| --- | --- |
| Client | `bash`, OpenSSH client (`ssh`, `ssh-keygen`, `ssh-agent`, `ssh-add`, `ssh-keyscan`), `awk`, `sed`, `host` (DNS lookups) |
| vsh-host | `bash`, OpenSSH server, `logger`, and a container runtime: OpenVZ (`vzctl`/`vzlist`/`vzmigrate`), Virtuozzo (`prlctl`), LXC (`lxc-ls`, `lxc-attach`, `lxc-info`, ...) or Solaris zones (`zoneadm`, `zlogin`). A host used only for proxying needs no runtime. |
| Containers (only for `vsh -x`) | `/usr/sbin/sshd` and X11 client libraries/`xauth` inside the container |

## Client

### 1. Install the script

Put `vsh` somewhere in `$PATH`. That can be `~/bin` for a single user, or
`/usr/local/bin` or `/usr/bin` on a shared admin machine. It **must** be
callable as `vsh`, because the script calls itself (`vsh -H`) to tell hosts
and containers apart.

Optionally install the helpers from `contrib/` (see [CONTRIB.md](CONTRIB.md)).

### 2. Create the template and your keys

```
$ vsh -t
/home/alice/.vsh/hosts created.

Please add vsh-hosts to this file.

Creating default keys:
Enter passphrase (empty for no passphrase):
Enter same passphrase again:
/home/alice/.vsh/keys/vsh-alice-user generated

Distribute this to ~root/.ssh/authorized_keys on all vsh-hosts:

command="/opt/vsh/bin/vshd user=alice" ssh-rsa AAAAB3NzaC1yc2E... vsh-alice-user
```

`vsh -t` creates:

* `~/.vsh/hosts`: an empty hostfile.
* `~/.vsh/var/`: the state directory.
* `~/.vsh/keys/`, holding:
  * an **X11 key**, without a passphrase, used only by `vsh -x`. It is never distributed.
  * your **user key**, which you should give a strong passphrase. Its
    `.dist.pub` file is what you hand to the vsh-host administrators.

Need more roles? Run `vsh -g <role>`, for example `vsh -g admin`. That
creates `vsh-alice-admin.dist.pub` with `user=alice+admin`. See
[VSHD-INI.md → Roles](VSHD-INI.md#roles).

### 3. Fill in the hostfile

```
# ~/.vsh/hosts
# Only the first word of each line is used; the rest is a free-form comment.
vsh-host1.example.com     # rack 3
vsh-host2.example.com     00:11:22:33:44:55   (MAC, used by the wol module)
proxyuser@jump.example.com  # connect as a non-root user (see below)
#retired-host.example.com
```

* By default `vsh` connects as `root`. Use `user@host` to connect to a
  `vshd` that runs as an unprivileged user.
* Several admins can share one file. Point `VSH_HOSTFILE` at it.

### 4. Collect host keys

Run `vsh -t` again. Now that the hostfile is not empty, it runs
`ssh-keyscan` against every host and merges the result into
`~/.ssh/known_hosts`. It also keeps a backup as
`~/.ssh/known_hosts.vshtmp`. `vsh` relies on known host keys, since it
never asks interactively.

`ssh-keyscan` ignores `~/.ssh/config` and cannot handle `user@host`
entries. For such hosts, and for hosts on a non-standard port, connect once
by hand to accept the host key, e.g.
`ssh -i ~/.vsh/keys/vsh-$USER-user proxyuser@jump.example.com list`.

### 5. Hand over your key

Send `~/.vsh/keys/vsh-<login>-*.dist.pub` to your vsh administrators. If the
team uses a shared drop folder, `vsh -d` copies all of your `.dist.pub`
files there (default `/tmp/<login>/`, or set `VSH_DISTKEYFOLDER`).

## Server (vsh-host)

### 1. Lay out `/opt/vsh`

```sh
git clone https://github.com/yownas/vsh.git ~/sandbox/vsh
mkdir -p /opt/vsh/{bin,etc,libexec,modulesd}

cd ~/sandbox/vsh
cp -p vshd                /opt/vsh/bin/
cp -p libexec/*           /opt/vsh/libexec/
cp -p etc/vshd.ini        /opt/vsh/etc/
cp -p etc/proxy-clients   /opt/vsh/etc/    # optional, see PROXY-CLIENTS.md
cp -p modulesd/*          /opt/vsh/modulesd/  # optional, see MODULES.md
cp -p vsh                 /opt/vsh/bin/    # only for "* vsh:" proxying
chmod 755 /opt/vsh/bin/* /opt/vsh/libexec/*
```

Resulting tree:

```
/opt/vsh/
├── bin/
│   ├── vshd
│   └── vsh                 (optional)
├── etc/
│   ├── vshd.ini
│   └── proxy-clients       (optional)
├── libexec/
│   ├── vshd-Linux          (chosen by `uname`, must be executable)
│   ├── vshd-SunOS
│   └── vshd-FreeBSD
└── modulesd/               (optional)
```

`vshd` picks the backend `libexec/vshd-$(uname)` and stops with
`error: ... not found` if that file is missing or not executable.

To install somewhere other than `/opt/vsh`, change `vshprefix` at the top
of `vshd`. Also change the `command="..."` path in every key, because
`vsh -g` hard-codes `/opt/vsh/bin/vshd`. See [VSHD.md](VSHD.md#configuration-variables).

### 2. Write `vshd.ini`

See [VSHD-INI.md](VSHD-INI.md) for the full reference. A minimal file
looks like this:

```ini
[groups]
wheel:alice,bob

[containers]
*:@wheel

[hosts]
*:@wheel

[operations]
move:@wheel
startstop:@wheel

[modules]
*:@wheel
```

### 3. Install user keys

Append each user's `.dist.pub` line(s) to `~root/.ssh/authorized_keys`:

```
command="/opt/vsh/bin/vshd user=alice" ssh-rsa AAAAB3Nza...P vsh-alice-user
command="/opt/vsh/bin/vshd user=alice+admin" ssh-rsa AAAAB3Nza...5 vsh-alice-admin
```

A forced command does **not** stop a key from forwarding ports. Without
further options, any vsh user can run `ssh -N -L ...` and tunnel through
the vsh-host as root. vsh needs none of these features on this hop, so
prefix every line with restrictions when you install it:

```
restrict,pty,command="/opt/vsh/bin/vshd user=alice" ssh-rsa AAAAB3Nza...P vsh-alice-user
```

On OpenSSH older than 7.2, which lacks `restrict`, use
`no-port-forwarding,no-agent-forwarding,no-X11-forwarding,no-user-rc`
instead.

sshd must allow root logins with keys (`PermitRootLogin prohibit-password`
or `forced-commands-only`). `forced-commands-only` is the tightest
setting, and it works for vsh because every vsh key carries a
`command=`.

For a proxy-only host, consider running `vshd` as an unprivileged user
instead. See [Running vshd without root](#running-vshd-without-root).

### Vetting keys before installing them

The whole security model depends on this step. For every `.dist.pub` you
receive, check:

* The `user=` value is the identity this person should have. A user can
  edit their `.dist.pub` and write `user=bob`.
* The command is exactly `/opt/vsh/bin/vshd user=<name>`, with no other
  arguments. Ignore any options the user wrote into the key line and apply
  your own (`restrict,pty`, see above).
* The file came from its owner, for example it is owned by and writable
  only by that user if you collect from a shared folder.
* No two people share a key: compare the key material. A duplicate may mean
  someone is trying to pass their privileges to another person.
* Install keys only on hosts the user actually needs.

With many admins, script this step: gather the files, check them, build
`authorized_keys` and push it with Puppet, Ansible or cfengine. Encourage
users to rotate keys (`rm ~/.vsh/keys/vsh-$USER-user*; vsh -g`) rather
than only changing the passphrase.

### 4. Test

```sh
vsh -p -o athosts hostname
vsh -l
```

If you get `permission denied`, check `vshd.ini` and the syslog on the
vsh-host (see [TROUBLESHOOTING.md](TROUBLESHOOTING.md)).

## Running vshd without root

If a `vshd` only proxies SSH connections and never enters local containers,
it does not need root:

1. Create a user such as `vshproxy` and install vsh under a path it can
   read, then set `vshprefix` in its copy of `vshd`.
2. Put the vsh keys in `~vshproxy/.ssh/authorized_keys`, with `command=`
   pointing at that `vshd`.
3. Give `vshproxy` its own SSH key on the proxy clients.
4. In the clients' hostfiles, write `vshproxy@jump.example.com`.

This way one machine can also run **several independent `vshd`
instances**, each with its own users, keys, `vshd.ini` and proxy list. For
example, the network team and the DBA team can each have their own.

## Upgrading

Copy the new `vsh`, `vshd` and `libexec/*` over the old ones. `vshd.ini`,
`proxy-clients`, keys and the hostfile keep their format. Keep the
client and the servers at roughly the same version, because the protocol
between them is just the action words listed in [VSHD.md](VSHD.md#actions).
