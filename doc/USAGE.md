# Usage & recipes

Day-to-day examples. For every flag, see [VSH.md](VSH.md). For setup, see
[INSTALL.md](INSTALL.md).

## First-time user setup

If vsh and vshd are already installed by your administrators:

```sh
vsh -t                     # creates ~/.vsh, generates your keys, prints your key line
```

Send the printed `command="..."` line (or `~/.vsh/keys/*.dist.pub`, or run
`vsh -d`) to your administrator. Once it is installed, add the vsh-hosts
you were given to `~/.vsh/hosts`, one per line, and run `vsh -t` again to
record their host keys. `vsh -l` should now list containers.

## Typing your passphrase once a day

```sh
eval $(ssh-agent)          # skip if your desktop already runs an agent
vsh -a -l                  # loads your key for 9 hours (VSH_KEYLIFE)
vsh -k admin -a -l         # same for your admin role
```

Or keep vsh keys in a separate agent with `vsh-agent`. See
[CONTRIB.md](CONTRIB.md#vsh-agent).

## Finding things

```sh
vsh -l                     # all container names
vsh -ll | grep db          # name@host: where does each db live?
vsh -lll                   # host, name, id, status
vsh -u -l                  # instant, from cache (no network)
vsh -H                     # the vsh-hosts in your hostfile
```

## Getting in

```sh
vsh web01                          # root shell
vsh web01 systemctl restart nginx  # one command
vsh -x web01                       # full TTY + X11 (screen, vi, virt-manager...)
vsh -h web01                       # shell on the host that runs web01
vsh -H vsh-host2                   # shell on a specific vsh-host
vsh -k admin web01                 # use a different role
```

## Running things everywhere

```sh
# On every vsh-host, output prefixed with the host name
vsh -p -o athosts 'uptime'

# In a list of containers, from a file or a pipe
vsh -p -o atct 'rpm -q openssl' < webservers.txt
vsh -u -l | grep '^web' | vsh -u -p -o atct 'df -h /'
```

`atct` handles the targets one at a time, in the order given, and drops
adjacent duplicates. Each target needs `[containers]` permission. Targets
you lack access to print `permission denied` and the run continues. A name
vsh cannot find at all aborts the whole run, unless you use `-p`, which
reports it and carries on.

When you pipe one `vsh` into another, give both `-u` (refresh first with a
plain `vsh -l` if needed). Otherwise both refresh the statefile at once and
can corrupt each other's results. For long runs, load your key with `vsh -a`
first. The temporary key only lasts 30 seconds.

## Copying files

```sh
vcp ./nginx.conf web01:/etc/nginx/            # scp style
rsync -av -e vsh ./site/ web01:/var/www/      # rsync style
vshcopy web01:/var/log/nginx ./web01-logs     # tar stream, no scp needed (not for LXC)
```

See [CONTRIB.md](CONTRIB.md).

## Container lifecycle (OpenVZ/Virtuozzo/LXC/zones)

```sh
vsh -o stop web01
vsh -o start web01
vsh -k admin -o move web01 vsh-host2          # live if running
vsh -k admin -o move-offline web01 vsh-host2  # when live migration fails (e.g. special features)
```

## Emptying a host for maintenance

```sh
vsh -k admin -o moveall vsh-host1 vsh-host2 vsh-host3   # round-robin onto 2 and 3
vsh -H vsh-host1 'yum -y update && reboot'
# ...afterwards, move them back one by one with -o move
```

Only OpenVZ/Virtuozzo containers can be migrated. A `moveall` on a host
that also has LXC containers stops at the first LXC container.

## Working when a host is down

Every command refreshes the state from **all** hosts, with a 4-second
connect timeout each (in parallel). If a host is down, or its DNS is one of
the containers you are moving, skip the refresh:

```sh
export VSH_UPDATE=0        # or use -u on each call
vsh web01
```

The cache can be out of date. Run a plain `vsh -l` once things are back.

## Sharing a hostfile in a team

```sh
# in a shared profile
export VSH_HOSTFILE=/srv/admin/vsh-hosts
```

## Root on machines without containers

Ask the vsh admin to add them to `proxy-clients`
([PROXY-CLIENTS.md](PROXY-CLIENTS.md)). After that, `vsh <alias>` works
like any container.

## Waking up powered-off hosts

```sh
vsh -M wol 'vsh-host[3-4]'     # MACs from column 2 of your hostfile
```

See [MODULES.md](MODULES.md).

## Rotating your key

```sh
rm ~/.vsh/keys/vsh-$USER-user ~/.vsh/keys/vsh-$USER-user.*
vsh -g                          # new key + new .dist.pub
vsh -d                          # or send the .dist.pub to your admins
```

Ask the admins to remove the old line from `authorized_keys`.
