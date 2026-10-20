# Server reference: `vshd`

`vshd` is never run by hand. sshd starts it as the forced command of a vsh
key:

```
command="/opt/vsh/bin/vshd user=alice" ssh-rsa AAAA... vsh-alice-user
```

* `user=<name>` (the command-line argument) is the **identity**. The
  default is `nobody`, which matches no permissions.
* `$SSH_ORIGINAL_COMMAND` (whatever the client asked to run) is the
  **request**. Any request containing non-printable characters is
  rejected.

## Actions

These are the words the `vsh` client sends. You only need them when
writing your own client tooling or modules.

| Request | Permission (`vshd.ini`) | Does |
| --- | --- | --- |
| `list` | none | Prints `host name id/path status` for every local container, then the proxy clients. |
| `run <ct> [<cmd>]` | `[containers] <name>` | Shell or command in a container or proxy client, as root or the run-as user. |
| `hostrun [<cmd>]` | `[hosts] <hostname>` | `/bin/bash -il`, or `eval <cmd>`, on the vsh-host. |
| `start <ct>` / `stop <ct>` | `[operations] startstop` | Start or stop a container. |
| `move <ct> <host>` | `[operations] move` | Migrate live if running, otherwise offline. |
| `move-offline <ct> <host>` | `[operations] move` | Migrate offline. |
| `moveall <host> [<host>...]` | `[operations] move` | Migrate all local containers round-robin to the given hosts. |
| `moveall-offline <host> [...]` | `[operations] move` | Same, offline. |
| `module <name> [<args>]` | `[modules] <name>` | Source `modulesd/<name>`. |
| `usage` / anything else | none | Print usage. |

## Configuration variables

These are set at the top of the `vshd` script. Edit the script to change
them; there is no separate config file for them.

| Variable | Default | Meaning |
| --- | --- | --- |
| `vshprefix` | `/opt/vsh` | Installation root. Everything below is relative to it. |
| `vshdexec` | `$vshprefix/libexec/vshd-$(uname)` | OS backend. |
| `vshdini` | `$vshprefix/etc/vshd.ini` | Permissions, see [VSHD-INI.md](VSHD-INI.md). |
| `vshdproxy` | `$vshprefix/etc/proxy-clients` | Proxy list, see [PROXY-CLIENTS.md](PROXY-CLIENTS.md). Optional. |
| `moduledir` | `$vshprefix/modulesd` | Server-side modules. |
| `VSH_BIN` | `$vshprefix/bin/vsh` | vsh client used for `vsh:` proxying. |
| `logpriority` | `info` | syslog priority for normal log lines. |
| `errorpriority` | `err` | syslog priority for denials and errors. |

`vshd` also unsets `VSH_HOSTFILE`, so a `vsh` started by `vshd` for
`vsh:` proxying always uses the server user's own `~/.vsh/hosts`.

## Logging

Everything goes through `logger`, tagged `vshd (<pid>)`:

```
vshd (12345): ARG: user=alice CMD: run 101
vshd (12345): run alice web01.example.com (101)
vshd (12345): end session: alice
vshd (12346): error: run permission denied for eve@web01.example.com ()
```

(The id in parentheses is empty on denials. It is only filled in once
access has been granted.)

The priorities are plain `logger -p` values, so they can include a
facility. To route vsh logs to their own file, set for example
`logpriority=local3.info` and `errorpriority=local3.err` and add a matching
rsyslog rule. Forward these logs to a central log server, since they are
your audit trail. Errors are also echoed to the client as `error: ...`.

## Platform backends

`libexec/vshd-<uname>` is sourced by `vshd` and must define these
functions:

| Function | Contract |
| --- | --- |
| `vsh_list` | Print one line per container: `<vsh-hostname> <name> <id/path> <status>`. |
| `vsh_cttoname` | Given `$ct` (an id/path), set `vsh_return` to the name used for permission checks. |
| `vsh_login <user> <ct> [<cmd>]` | Enter `<ct>` as `<user>`: a shell if `<cmd>` is empty, otherwise run it. |
| `vsh_start <ct>`, `vsh_stop <ct>` | Start or stop. |
| `vsh_movect live\|offline <ct> <host>` | Migrate. |

### Linux (`vshd-Linux`)

Supports **Virtuozzo** (`prlctl`, preferred if installed), **OpenVZ**
(`vzctl`, `vzlist`, `vzmigrate`) and **LXC** (`lxc-*`), side by side on the
same host.

| Feature | OpenVZ / Virtuozzo | LXC |
| --- | --- | --- |
| list | `vzlist -Hat -o hostname,ctid,status` / `prlctl list -ao hostname,ctid,status` | `lxc-ls -f`, id shown as `lxc:<name>` |
| name for permissions | container hostname | LXC name |
| enter / exec as root | `vzctl enter` / `vzctl exec` (`prlctl enter` / `exec`) | `lxc-attach -n <name> -- bash -i` / `-- <cmd>` |
| run-as user | `su - <user>` via `vzctl` (not for `prlctl`) | not supported |
| start / stop | `vzctl` / `prlctl` | `lxc-start -d` / `lxc-stop` |
| migrate | `vzmigrate --live` (if running) / `prlctl migrate` | not supported |

**Migration requirements:** the source vsh-host's root must be able to SSH
to the destination host's root **without a password**. vsh calls the
migration tool with `BatchMode=yes` and `StrictHostKeyChecking=no`.
`vzmigrate` runs with `--remove-area no --keep-dst`, so the private area on
the source is kept, and so is a destination left over from a failed
attempt. Clean these up yourself.

### Solaris (`vshd-SunOS`)

Lists zones with `zoneadm list -vi` (the global zone is excluded) and
enters them with `zlogin`. Run-as users use `su -`. Start and stop use
`zoneadm boot` and `zoneadm halt`. Migration is not implemented.

### FreeBSD (`vshd-FreeBSD`)

A skeleton only: every function prints `NOT IMPLEMENTED`, and
`vsh_cttoname` is missing. `hostrun` and modules work. The `NOT IMPLEMENTED`
line from `vsh_list` is parsed by the client as a container named `NOT`,
so a bogus entry shows up in `vsh -l`. If you want jail support, this file
is the place to add it.

### Writing a backend

Copy `vshd-SunOS` (the smallest complete backend) to `vshd-$(uname)` for
your OS, implement the functions above and make the file executable.
`vshd-FreeBSD` is shorter but lacks `vsh_cttoname`. Keep the `vsh_list` output
format exactly as described: the client relies on column positions.
Look at how `vshd-Linux` handles the `lxc:` prefix if your platform needs
a namespace next to another one.
