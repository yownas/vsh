# vsh

*Vad Som Helst* (vzsh without the Z): a tool for managing containers that is
sometimes also good at managing root on other hosts.

vsh gives a team of admins audited, per-user root access to OpenVZ/Virtuozzo
and LXC containers, Solaris zones, and plain SSH hosts. Everything runs over
SSH, with two shell scripts and no agents or daemons to install:

* **`vsh`**: the client on your workstation. It finds which host runs a
  container and drops you into it.
* **`vshd`**: an SSH forced command on each vsh-host. It enforces the
  permissions in `vshd.ini` and logs to syslog.

```sh
vsh -l                         # list all containers on all hosts
vsh web01                      # root shell in web01
vsh web01 systemctl status nginx
vsh -p -o athosts uptime       # run on every vsh-host
vsh -k admin -o move web01 vsh-host2
```

## Install in brief

**Client:** put `vsh` in your `$PATH`, run `vsh -t`, add your vsh-hosts to
`~/.vsh/hosts`, then run `vsh -t` again.

**Server:** copy `vshd` → `/opt/vsh/bin/`, `libexec/*` → `/opt/vsh/libexec/`
and `etc/vshd.ini` → `/opt/vsh/etc/`. Add your username to `vshd.ini` and
put your `~/.vsh/keys/*.dist.pub` in `~root/.ssh/authorized_keys`.

## Documentation

The full user guide lives in [`doc/`](doc/README.md):

* [Concepts](doc/CONCEPTS.md): how it works, and the security model
* [Quickstart](doc/QUICKSTART.md) and [Installation](doc/INSTALL.md)
* [`vsh` client reference](doc/VSH.md) and [`vshd` server reference](doc/VSHD.md)
* [Access control (`vshd.ini`)](doc/VSHD-INI.md)
* [Proxy clients](doc/PROXY-CLIENTS.md), [Modules](doc/MODULES.md), [Contrib tools](doc/CONTRIB.md)
* [Usage & recipes](doc/USAGE.md), [Troubleshooting](doc/TROUBLESHOOTING.md)

## License

See [LICENSE](LICENSE).
