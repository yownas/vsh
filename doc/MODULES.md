# Modules

Modules are small scripts that extend vsh without changing the core
scripts. A module can have two halves:

| Half | Location | Runs | Started by |
| --- | --- | --- | --- |
| Client | `~/.vsh/modules/<name>` | on your workstation, **sourced** into `vsh` | `vsh -M <name> [args]` |
| Server | `/opt/vsh/modulesd/<name>` | on the vsh-host, **sourced** into `vshd` as root | the client half, with `vsh_ssh <host> module <name> [args]` |

The server half is permission checked under `[modules]` in
[`vshd.ini`](VSHD-INI.md#modules-server-side-modules). The client half is
not, since it runs as you on your own machine.

## Installing

```sh
mkdir -p ~/.vsh/modules
cp modules/* ~/.vsh/modules/            # client halves
cp modulesd/* /opt/vsh/modulesd/        # server halves, on each vsh-host
```

## Bundled modules

### `list`: list available modules

```sh
vsh -M list        # name + first line of each module
vsh -M list -l     # name + full header (everything up to a line containing only "##")
```

### `qc`: quick check of all containers

```sh
vsh -M qc          # top 5 per metric
vsh -M qc 10       # top 10
```

It runs the server half on every vsh-host and shows, for each metric, the
containers with the highest values: **disk usage** (`df`), **load
average** and **number of processes**. It needs the server half in
`modulesd/qc` and the `qc` permission. **OpenVZ only**, since it uses
`vzlist` and `vzctl exec`.

### `wol`: Wake-on-LAN for vsh-hosts

```sh
vsh -M wol vsh-host3
vsh -M wol 'vsh-host[1-5]'      # awk regular expression against the hostfile
```

It reads MAC addresses from the **second column** of your hostfile:

```
vsh-host3.example.com  00:11:22:33:44:55
```

Edit these variables at the top of `~/.vsh/modules/wol`:

| Variable | Default | Meaning |
| --- | --- | --- |
| `broadcast` | `192.168.1.255` | Broadcast address to send to |
| `wolcmd` | `socat - udp-datagram:${broadcast}:7,broadcast` | Sender. An `nc -w 1 -u ${broadcast} 7` alternative is included, commented out |
| `packets` | `2` | Packets per host |

It needs `dc` plus `socat` (or `nc`). It runs entirely on the client.

## Writing a module

### Client half

The file is *sourced* (`. ~/.vsh/modules/<name> <args>`) after `vsh` has
loaded your key. Inside it you can use:

| Name | What |
| --- | --- |
| `$1`, `$2`, ... / `$args` | Arguments after the module name |
| `$hostfile`, `$vsh_hosts` | Hostfile path / space-separated host list |
| `$statefile` | Container cache (`host name id status`) |
| `$modules` | Client module directory |
| `vsh_ssh <host> <request...>` | Send a raw `vshd` request (`list`, `run`, `hostrun`, `module`, ...) with your key |
| `VSH_SSH_OPTS` | Extra ssh options for the **next** `vsh_ssh` call only, e.g. `-o LogLevel=QUIET` or `-t` |
| `vsh` | The command itself, e.g. `vsh -H` to list hosts or `vsh -u -lll` |

Conventions: the first line is a one-line description, and the help text
ends with a line containing only `##` so that `vsh -M list -l` can show it.

Example `~/.vsh/modules/kernels`:

```sh
# Show running kernel on every vsh-host
#
# Usage:
#   vsh -M kernels
##
for h in $vsh_hosts; do
  VSH_SSH_OPTS="-o LogLevel=QUIET"
  printf '%-30s %s\n' "$h" "$(vsh_ssh $h hostrun uname -r)"
done
```

### Server half

The file is sourced by `vshd` **as root** after the permission check. Any
arguments sent after the module name are in `$ccmd`. Note that `$1`, `$2`
and so on are *not* the module arguments. `$user` holds the calling
identity, and every backend function (`vsh_list`, `vsh_login`, ...) is
available.

Example `/opt/vsh/modulesd/ctcount`:

```sh
# Server part of 'ctcount': count local containers per status
vsh_list | awk '{n[$4]++} END {for (s in n) print "'$(hostname)'", s, n[s]}'
```

Client half (`~/.vsh/modules/ctcount`):

```sh
# Count containers per status on every host
##
for h in $vsh_hosts; do VSH_SSH_OPTS="-o LogLevel=QUIET"; vsh_ssh $h module ctcount; done
```

Avoid calling `vsh_login` with a command from a server module. Its root
code path checks the global `$ccmd`, which here holds the module
arguments, rather than its own argument. Call the runtime directly
instead (`vzctl exec`, `lxc-attach`, ...), as `modulesd/qc` does.

Remember that a server module is root code reachable by anyone with the
right `[modules]` entry. Treat its input (`$ccmd`) as untrusted.
