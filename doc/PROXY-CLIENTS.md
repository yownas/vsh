# Proxy clients

A vsh-host can act as a **jump host**: through `vshd`, it gives users root
(or another account) on machines that have no container runtime and no
vsh installation. Those machines only need to accept SSH from the vsh-host.

This gives you:

* one root key per jump host, instead of one key per admin on every server,
* access control and logging in `vshd.ini` and syslog,
* friendly aliases for hosts with long names or no DNS.

## File: `/opt/vsh/etc/proxy-clients`

```
# <alias>        ssh:[user@]<hostname|fqdn|ip>[:port]
ns1.example.com  ssh:ns1.example.com
web              ssh:webserver.with.a.very.long.name.example.com
gw               ssh:192.168.0.1
switch1          ssh:10.0.0.5:2222
dbroot1          ssh:dbhost1
dbadmin1         ssh:mysql@dbhost1

# Proxy everything that this host's own vsh client can reach (experimental)
*                vsh:
```

* Columns are separated by whitespace. Lines starting with `#` are ignored.
* **alias**: the name users type (`vsh web`). It is also the name checked
  under `[containers]` in `vshd.ini`.
* **target**:
  * `ssh:host`: run `ssh <run-as>@host`. The run-as user defaults to
    root and can be changed in `vshd.ini`.
  * `ssh:user@host`: always log in as `user`, ignoring the run-as setting.
    The `dbroot1`/`dbadmin1` pair above shows how two aliases can give
    different access to the same host.
  * `ssh:host:port`: non-standard SSH port. It is turned into
    `ssh host -p port`.
  * `vsh:`: see [Chaining vsh](#chaining-vsh-vsh) below.

## Setting up an SSH proxy client

On the vsh-host, as the user `vshd` runs as (normally root):

```sh
[ -f ~/.ssh/id_rsa ] || ssh-keygen          # key without passphrase (vshd runs non-interactively)
ssh-copy-id root@client.example.com
ssh root@client.example.com true            # accept the host key once
echo "client ssh:client.example.com" >> /opt/vsh/etc/proxy-clients
```

Then grant access in `vshd.ini`:

```ini
[containers]
client:@wheel
```

(`*:@wheel` covers it too, but `*` also opens every other machine the
`vshd` user's key can reach. See
[VSHD-INI.md → What is not access controlled](VSHD-INI.md#what-is-not-access-controlled).)
Users will now see it in `vsh -l`, with status
`proxy`, and can run `vsh client` or `vsh client uptime`.

Options for the outgoing hop, such as `IdentityFile`, `ProxyJump` or
`StrictHostKeyChecking`, go in `~/.ssh/config` of the user `vshd` runs as.

## Several vsh-hosts serving the same alias

If two vsh-hosts list the same alias, the client cannot tell which one you
mean and behaves unpredictably. Either make the alias point to the same
target on every vsh-host, or give each alias a single home.

## Chaining vsh: `vsh:`

`* vsh:` makes `vshd` run its **own** `vsh` client (`/opt/vsh/bin/vsh`), as
the user `vshd` runs as, and publish everything that client can see. This is
useful for networks behind NAT where only one machine is reachable.

Requirements:

* `vsh` installed as `/opt/vsh/bin/vsh` on the vsh-host.
* The `vshd` user (root) has a working `~/.vsh/` with a hostfile, and its
  vsh user key has **no passphrase**.
* That key is installed on the inner vsh-hosts.

Caveats: this feature is **experimental**. Every user permitted on the
outer host acts with the outer host's root identity on the inner network,
and the inner `vshd.ini` sees only that one identity. Only an interactive
shell is supported; any command you pass is ignored. Only the `*` form
exists, so you cannot pick individual inner containers. The `[containers]`
check on the outer host uses the inner **id/path** (e.g. `101`), not the
container name, so in practice only `*:` lines apply.

## Use cases

* **Bastion for a server room:** one vsh-host per site, with every
  physical server listed in `proxy-clients`. Admins never get personal
  accounts on the servers.
* **Network gear with SSH:** `core-sw ssh:admin@10.0.0.1`, restricted to
  `@netops` in `vshd.ini`.
* **Non-root service accounts:** `app1-deploy ssh:deploy@app1` for a
  deploy team that must never become root.
* **Unprivileged proxy:** when a host only proxies, run `vshd` as a normal
  user. See [INSTALL.md → Running vshd without root](INSTALL.md#running-vshd-without-root).
