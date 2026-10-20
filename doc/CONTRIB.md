# Contrib tools

Optional helpers in [`contrib/`](../contrib/). Install them on the client
next to `vsh`, somewhere in `$PATH`.

## `vcp`: scp over vsh

```sh
vcp localfile web01:/tmp/
vcp web01:/etc/hosts .
```

`vcp` is simply `scp -S vsh $*`. Because `$*` is unquoted, file names with
spaces are split apart ([upstream #14](https://github.com/yownas/vsh/issues/14)).
When scp calls `vsh` as if it were
`ssh` (`vsh -x <ssh options> <host> scp -t <path>`), vsh recognises the
pattern, drops the ssh options and runs `scp` inside the container. Use it
either as a script (`contrib/vcp`) or as a shell function (source
`contrib/vcp.alias` from `~/.bashrc`).

Pick a role with `VSH_KEY=admin vcp ...`, because scp cannot pass `-k`.

The scp protocol support depends on scp's legacy mode. With OpenSSH 9+ use
`scp -O -S vsh ...` (or edit `vcp`) so scp does not try SFTP.

## `rsync -e vsh`

rsync calls its remote shell as `<rsh> <host> rsync --server ...`, which
vsh handles as an ordinary `vsh <container> <command>`:

```sh
rsync -av -e vsh ./site/ web01:/var/www/html/
rsync -av -e 'vsh -k admin' web01:/etc/ ./web01-etc/   # or VSH_KEY=admin
```

`rsync` must be installed in the container.

## `vshcopy`: copy with tar over vsh

```sh
vshcopy [<ct>:]<file|dir> [<ct>:]<dir>

vshcopy ./configs web01:/root/          # local → container
vshcopy web01:/var/log/app ./logs       # container → local
vshcopy web01:/srv/data web02:/srv/     # container → container (streams through your workstation)
```

It streams `tar -cf -` on the source into `tar -xvf -` on the destination.
Modes come along. Ownership is kept only where the extracting side runs
as root. It needs only `tar` and a shell in the containers: no scp, no
rsync. It does **not** work with LXC containers, because vshd runs LXC
commands without a shell and the `cd ... && tar ...` fails there.

## `vsh-agent`

A wrapper around `ssh-agent` that exports **`VSH_AUTH_SOCK`/`VSH_AGENT_PID`**
instead of `SSH_*`. vsh keys then live in their own agent, separate from
your everyday SSH keys, so a forwarded agent never carries them and other
tools never offer them to the wrong host.

```sh
eval $(vsh-agent)        # start
vsh-agent -a ~/.vsh/keys/vsh-$USER-user   # add key
vsh-agent -l             # list keys (-L for full public keys)
vsh-agent -d <key>       # remove one key, -D removes all
vsh-agent -e             # print export lines to paste into another terminal
eval $(vsh-agent -k)     # stop
```

`vsh` itself uses `VSH_AUTH_SOCK` whenever it is set. If no agent can be
reached at all and `vsh-agent` is in `$PATH`, `vsh` starts one and saves
its environment to `~/.vsh/var/<fqdn>.agent`. Later `vsh` runs in any
terminal on that machine reuse it. Load the key into it once with `vsh -a`
(or `vsh-agent -a`) to type your passphrase only once. If the saved agent has died
(e.g. after a reboot), vsh starts a new one and replaces the file.

## Bash completion

```sh
source contrib/vsh-complete.bash      # or add to ~/.bashrc
vsh we<TAB>                           # → web01.example.com
```

It completes container names from the cached statefile
(`~/.vsh/var/ctstate`) and never contacts the hosts. Refresh the cache
with a plain `vsh -l` now and then.
