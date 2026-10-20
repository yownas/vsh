# Concepts

## Vocabulary

| Term | Meaning |
| --- | --- |
| **vsh-host** | A machine running `vshd`. It is usually a container hypervisor (OpenVZ/Virtuozzo, LXC, Solaris zones) or a jump host that proxies SSH. |
| **container** | Anything `vshd` can put you into: an OpenVZ/Virtuozzo container, an LXC container, a Solaris zone, or a *proxy client*. |
| **proxy client** | A plain SSH host that `vshd` connects to on your behalf. See [PROXY-CLIENTS.md](PROXY-CLIENTS.md). |
| **user** | Your identity as `vshd` sees it. It comes from the `user=` argument baked into your public key, *not* from your Unix login. |
| **role** | A second identity of the same person, backed by a separate key, e.g. `alice+admin`. See [Keys and roles](#keys-and-roles). |
| **hostfile** | `~/.vsh/hosts`, the list of vsh-hosts the client talks to. |
| **statefile** | `~/.vsh/var/ctstate`, the client's cache of which container lives on which host. |

## Architecture

```
 workstation                     vsh-host (as root)
 ┌──────────┐   ssh root@host    ┌──────────────────────────────┐
 │  vsh     │ ─────────────────▶ │ sshd                         │
 │          │  key: vsh-me-user  │  └─ authorized_keys:         │
 │ ~/.vsh/  │                    │     command="/opt/vsh/bin/   │
 │  hosts   │  SSH_ORIGINAL_     │       vshd user=me"          │
 │  keys/   │  COMMAND="run 101" │        │                     │
 │  var/    │                    │        ▼                     │
 └──────────┘                    │  vshd ── vshd.ini (perms)    │
                                 │   ├─ libexec/vshd-Linux ─────┼─▶ vzctl / prlctl / lxc-attach ─▶ container
                                 │   ├─ etc/proxy-clients ──────┼─▶ ssh ─▶ remote host
                                 │   └─ modulesd/<module>       │
                                 └──────────────────────────────┘
```

1. `vsh` always connects as `root@<vsh-host>` (or as `user@host` if the
   hostfile entry says so), using **your personal vsh key**.
2. On the vsh-host, the key in `~root/.ssh/authorized_keys` has a forced
   command: `command="/opt/vsh/bin/vshd user=alice"`. Whatever command `vsh`
   asked for, sshd runs `vshd` instead and passes the request in
   `$SSH_ORIGINAL_COMMAND`.
3. `vshd` sources the backend for this OS (`libexec/vshd-$(uname)`). It parses
   the request (`run`, `list`, `hostrun`, `move`, ...), checks `vshd.ini`
   for the `user=` identity and then carries out the request.

Because the identity is tied to the **key** and fixed by sshd, you cannot
claim to be someone else just by sending a different command. You would
need another user's private key.

## How `vsh` finds a container

Before most actions, `vsh` refreshes its statefile. It runs `list`
**in parallel** on every host in the hostfile and caches the result:

```
<vsh-host>  <name>               <id/path>          <status>
vsh-host1   web01.example.com    101                running
vsh-host1   build                lxc:build          RUNNING
jump1       gw                   ssh:192.168.0.1    proxy
```

When you type `vsh web01.example.com`, the client:

1. Looks up the name in the statefile. If it is not there, it tries a DNS
   lookup with `host`.
2. Checks whether the name is itself a vsh-host in your hostfile. If so, it
   opens a shell on the host (`hostrun`) instead.
3. Otherwise it finds the host and the id/path (`101`, `lxc:build`,
   `ssh:...`) and sends `run <id/path> [command]` to that host.

Use `-u` (or `VSH_UPDATE=0`) to skip the refresh and trust the cache. This
is useful when a host is down or slow.

## Keys and roles

Each person generates one or more key pairs under `~/.vsh/keys/`:

| File | Purpose |
| --- | --- |
| `vsh-<login>-user`, `.pub` | Default key ("user" role). Passphrase protected. |
| `vsh-<login>-user.dist.pub` | Public key with the `command="/opt/vsh/bin/vshd user=<login>"` prefix, ready for `authorized_keys`. |
| `vsh-<login>-<role>`, `.pub`, `.dist.pub` | Extra role. Its identity is `<login>+<role>`. |
| `vsh-<login>-X11`, `.pub` | Passphrase-less key used only for `vsh -x` X11 forwarding. It is never distributed. |

You select a role with `-k <role>` or `VSH_KEY=<role>`. Roles let a person
work with low privileges by default and switch to more powerful
permissions on purpose, for example `alice` for daily work and
`alice+admin` for moving containers.

## Security model

* **Authentication** is SSH public-key only. `vsh` disables password
  authentication on its connections.
* **Identity** is the `user=` value in the forced command of the key used.
  It can be trusted only as far as the person who installs keys into
  `authorized_keys` checks them. See
  [INSTALL.md → Vetting keys](INSTALL.md#vetting-keys-before-installing-them).
* **Authorization** is `vshd.ini`, evaluated by shell scripts. Treat it as a
  convenience, not a hard boundary: *assume anyone with a vsh key on a host
  could get full root on that host.* Only give a host keys belonging to
  people you would trust with root there. Run separate vsh-hosts (or
  separate `vshd` instances under separate Unix users) for less trusted groups.
* **Audit**: `vshd` logs every request and every decision to syslog. See
  [VSHD.md → Logging](VSHD.md#logging).
* **Input sanitising**: `vshd` rejects requests that contain non-printable
  characters.
