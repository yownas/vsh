# Access control: `vshd.ini`

`vshd` reads its permissions from `/opt/vsh/etc/vshd.ini` (that is,
`$vshprefix/etc/vshd.ini`) on **every request**. Changes take effect right
away and nothing needs a restart. Each vsh-host has its own copy, so to
manage many hosts you usually distribute the file with a configuration
management tool.

A sample file ships in [`etc/vshd.ini`](../etc/vshd.ini).

## File format

```ini
# Comment lines start with '#'
[groups]
group:user1,user2

[containers]
<container>:<who>[,<who>...]

[hosts]
<hostname>:<who>[,<who>...]

[operations]
move:<who>[,<who>...]
startstop:<who>[,<who>...]

[modules]
<module>:<who>[,<who>...]
```

`<who>` is either a user (`alice`, `alice+admin`) or a group prefixed with
`@` (`@wheel`).

Parsing rules, which follow directly from the implementation:

* A section header must be alone on its line, at the start of the line, e.g.
  `[groups]`. Write it exactly like that.
* Lines starting with `#` are ignored. A `#` later in a line is **not**
  treated as a comment.
* Spaces are removed before matching, so `wheel: alice, bob` is fine. Tabs
  are not removed, so do not use them.
* The separator between the item and the list is **`:`**. `=` appears only
  in `[containers]`, to set a run-as user. Writing `wheel=alice` in
  `[groups]` silently breaks group membership.
* An item is either an exact name or `*`, meaning any. Patterns such as
  `web*` do not work. Strictly speaking, the *requested* name is used as a
  regular expression anchored to the start of the line, so the dots in
  `web01.example.com` match any character. This does not matter in
  practice.
* The same item may appear on several lines. All matching lines are
  checked.
* Permission is granted if **any** matching line lists the user or one of
  their groups. There are no deny rules
  ([upstream #7](https://github.com/yownas/vsh/issues/7)).

## `[groups]`

```ini
[groups]
wheel:alice,bob
admins:alice+admin
dba:carol,dave
```

Groups have one level only: a group cannot contain another group. A user
may be in several groups.

### Roles

A *role* is just a different user name of the form `<login>+<role>`. It
comes from a key generated with `vsh -g <role>` (see
[VSH.md → Keys](VSH.md#key-management)). To `vshd`, `alice` and
`alice+admin` are unrelated users: membership of one gives the other
nothing. In the example above, alice can move containers only when she
uses her admin key:

```sh
vsh -k admin -o move web01 vsh-host2
```

## `[containers]`: who may `run` in which container

```ini
[containers]
*:@wheel
syslog.example.com:eve=logmaster
db01.example.com:@dba=postgres,alice
```

The item is the **container name**, as `vshd` resolves it:

| Kind | Name used for the permission check |
| --- | --- |
| OpenVZ / Virtuozzo | The container's **hostname** (`vzlist -o hostname` / `prlctl list -o hostname`), not its CTID |
| LXC | The LXC container name |
| Solaris zone | The zone name |
| Proxy client | The **alias** (first column) from `proxy-clients` |
| `vsh:` chained client | The inner id/path (third column of the inner `vsh -lll`), not its name |

### Run-as users

By default you enter a container as **root**. Add `=<unix-user>` to a user
or group entry to enter as someone else instead:

```ini
# eve enters syslog as "logmaster"
syslog.example.com:eve=logmaster
# members of dba enter db01 as "postgres"
db01.example.com:@dba=postgres
```

Keep comments on lines of their own. A trailing `# ...` would become part
of the run-as user name.

How it is used:

* OpenVZ: `vzctl enter <ct> --exec exec su - <user>` for a shell, and
  `vzctl exec <ct> su - <user> -c '<cmd>'` for a command.
* Solaris: `zlogin <zone> su - <user>`.
* Proxy clients: `ssh <user>@<target>`. If the target in `proxy-clients`
  already contains `user@`, that user wins.
* LXC: **not supported.** Non-root access to LXC prints an error and exits.

Make sure that exactly one run-as user applies to any user/container pair.
If both a `*` line and a specific line give the same person different
run-as users, `vshd` gets several values and the login fails. Entries
without `=` never set a run-as user, so `*:@wheel` combined with
`syslog...:eve=logmaster` is fine.

## `[hosts]`: who may run commands on the vsh-host itself

Controls `hostrun`, which covers `vsh -H <host>`, `vsh -h <container>`,
`vsh -o athosts ...`, `vsh <vsh-host>` and modules that use `hostrun`.

```ini
[hosts]
*:@admins
vsh-host3.example.com:bob
```

The item is matched against the output of **`hostname`** on the vsh-host.
Depending on how the OS is set up, that is either a short name or an FQDN.
Use the form your hosts actually print. A good way to manage it is to
deploy one shared `vshd.ini` to all hosts: a line for a specific host only
has an effect on the host whose `hostname` matches it.

A user with `hostrun` is root on the vsh-host. In practice they also have
every container on it, whatever `[containers]` says.

## `[operations]`

| Item | Grants |
| --- | --- |
| `move` | `move`, `move-offline`, `moveall`, `moveall-offline` |
| `startstop` | `start`, `stop` |

```ini
[operations]
move:@admins
startstop:@admins,bob
```

## `[modules]`: server-side modules

The item is the module name (a file in `/opt/vsh/modulesd/`) or `*`.

```ini
[modules]
qc:@wheel
*:@admins
```

See [MODULES.md](MODULES.md).

## What is *not* access controlled

* **`list`**: every user with a key on a host sees all containers and proxy
  aliases on that host, including ones they may not enter.
* **`ssh:` targets outside `proxy-clients`**: a client can send
  `run ssh:<any-host>` directly. When `<any-host>` is not in
  `proxy-clients`, `vshd` checks `[containers]` against the bare host name.
  A `*:` line matches that name, and `vshd` then runs
  `ssh root@<any-host>` with its own key. So **`*:@group` under
  `[containers]` lets the group reach, as root, every machine that the
  `vshd` user's SSH key can log in to**, listed or not. On a host that has
  proxy clients, list containers by name instead of using `*`, or give
  the `vshd` user's key only to the machines in `proxy-clients`.
* Client-side modules run on your own workstation, so `vshd.ini` does not
  apply to them. Whatever they do on the server is checked as usual.

## Complete example

Three people: alice and bob are senior admins, carol is a DBA, and eve
handles logging.

```ini
[groups]
wheel:alice,bob
admins:alice+admin,bob+admin
dba:carol

[containers]
*:@wheel
db01.example.com:@dba=postgres
db02.example.com:@dba=postgres
syslog.example.com:eve=logmaster
# proxied switch, alias from proxy-clients
core-sw:@admins

[hosts]
*:@admins

[operations]
move:@admins
startstop:@admins,@wheel

[modules]
qc:@wheel,@dba
*:@admins
```

Result:

* alice/bob (user key) are root in every container. They can start and
  stop containers but cannot move them or log in on the hosts.
* alice/bob (admin key) can log in on every vsh-host, move containers,
  reach `core-sw` and run every module. They are **not** in `@wheel`, so
  entering containers still needs their user key. Add `@admins` to `*:`
  under `[containers]` if you want otherwise.
* carol is `postgres` on db01 and db02 and can run `qc`.
* eve is `logmaster` on the syslog container and can do nothing else.
