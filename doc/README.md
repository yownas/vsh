# vsh user guide

**vsh** (*Vad Som Helst*, Swedish for "whatever") is a pair of shell scripts.
They give a team of administrators controlled root access to containers,
hosts and other machines over plain SSH:

* **`vsh`**: the client. It runs on your workstation, keeps track of where
  every container lives, and connects you to it.
* **`vshd`**: the server side. It runs on each *vsh-host* as an SSH forced
  command and decides, based on `vshd.ini`, what each user may do.

## Contents

| Page | What it covers |
| --- | --- |
| [Concepts](CONCEPTS.md) | Architecture, the moving parts, how a request flows, the security model |
| [Quickstart](QUICKSTART.md) | Shortest path from zero to a root shell, using three example machines |
| [Installation](INSTALL.md) | Installing the client and server step by step, distributing and vetting keys |
| [Client reference (`vsh`)](VSH.md) | Every flag, action, environment variable and file used by `vsh` |
| [Server reference (`vshd`)](VSHD.md) | How `vshd` works, its variables, logging, platform backends |
| [Access control (`vshd.ini`)](VSHD-INI.md) | Groups, roles, container/host/operation/module permissions, run-as users |
| [Proxy clients](PROXY-CLIENTS.md) | Reaching plain SSH hosts (and other vsh networks) through `vshd` |
| [Modules](MODULES.md) | Bundled modules (`list`, `qc`, `wol`) and how to write your own |
| [Contrib tools](CONTRIB.md) | `vcp`, `vshcopy`, `vsh-agent`, bash completion |
| [Usage & recipes](USAGE.md) | Common workflows, start to finish |
| [Troubleshooting & limitations](TROUBLESHOOTING.md) | Common errors, quirks and known limitations |

## Five-minute tour

```sh
# Client: set up ~/.vsh and generate your keys
vsh -t

# Give the printed "command=..." line to whoever administers the vsh-hosts,
# then list the vsh-hosts in ~/.vsh/hosts
echo vsh-host1.example.com >> ~/.vsh/hosts
vsh -t                        # run again to collect the hosts' SSH host keys

vsh -l                        # list every container you can see
vsh web01                     # root shell in container web01
vsh web01 uptime              # run a command in it
vsh -H vsh-host1.example.com  # shell on the vsh-host itself
vsh -p -o athosts uptime      # run a command on every vsh-host
```

If you are new, read [Concepts](CONCEPTS.md) first and then follow the
[Quickstart](QUICKSTART.md) or the full [Installation](INSTALL.md) guide.
