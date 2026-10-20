# Troubleshooting & limitations

## Where to look

* **Client side:** run the failing command with plain ssh to see what
  happens:
  `ssh -v -i ~/.vsh/keys/vsh-$USER-user root@<vsh-host> list`
* **Server side:** syslog on the vsh-host. Each request is logged as
  `vshd (<pid>): ARG: user=<who> CMD: <request>`, followed by the outcome.
  See [VSHD.md → Logging](VSHD.md#logging).

## Common errors

| Symptom | Likely cause / fix |
| --- | --- |
| `ERROR: ~/.vsh/hosts missing or empty.` | Add hosts to the hostfile, or check `VSH_HOSTFILE`. |
| `ERROR: .../vsh-<login>-user or ...pub missing or empty.` | Run `vsh -t` or `vsh -g`. If you use roles, check `-k` / `VSH_KEY`. |
| Container missing from `vsh -l` | The host timed out (4 s), the key is not installed there, or the host key is unknown. Run `vsh -t` to collect host keys. Try `ssh -i <key> root@host list` by hand. |
| `getctname: Can not find container X` | Not in the statefile and not in DNS. Check the spelling against `vsh -l`. If you used `-u`, refresh with `vsh -l`. |
| `run: Container host not found.` | The name resolved via DNS, but no vsh-host lists it. |
| `error: run permission denied for alice@web01 ...` | No matching `[containers]` line. Remember that OpenVZ is checked by **hostname**, not CTID, and proxy clients by **alias**. |
| Permission denied although the user is in the group | `[groups]` written as `group=user` instead of **`group:user`**, a tab instead of spaces, or a header with trailing characters. See [VSHD-INI.md](VSHD-INI.md#file-format). |
| `hostrun permission denied` though `[hosts]` lists the host | `[hosts]` is matched against `hostname` on the server. That may be a short name where you wrote an FQDN, or the other way round. |
| Role key denied but user key works | `alice+admin` is a separate user. Add it to the groups or rules it needs. |
| `error: /opt/vsh/libexec/vshd-<OS> not found` | Backend not copied, or not executable (`chmod 755`). |
| `Permission denied (publickey)` | Key not in `~root/.ssh/authorized_keys`, sshd forbids root logins (`PermitRootLogin`), or the hostfile has the wrong `user@`. |
| Asked for a passphrase on every call, even after `vsh -a` | vsh cannot tell that the key is loaded and re-adds, then removes, it on every call. Set each key's comment to its path: see [VSH.md → Known problem](VSH.md#known-problem-the-key-is-never-seen-as-loaded). Also make sure an agent is reachable (`ssh-add -l`). |
| Passphrase asked again halfway through a long `atct`/`athosts`/`qc` run | The temporary key only lives 30 seconds. Load it with `vsh -a` first. |
| Temporary agent or key left behind after vsh exits on an error | Cleanup only runs at the normal end of the script ([upstream #6](https://github.com/yownas/vsh/issues/6)). Kill the agent by hand, or wait for the 30-second key lifetime to expire. |
| Output appears late, or all at once at the end, when piped (`vsh ct cmd \| grep`, `-p`, `atct`) | The remote program buffers its output because it is not writing to a TTY ([upstream #9](https://github.com/yownas/vsh/issues/9)). Force line buffering on the remote side: `vsh ct 'stdbuf -oL tail -f /var/log/messages' \| grep error`. |
| `vsh -x`: `Can not find X11-keys!` | `vsh -g X11`. |
| `vsh -x` fails inside the container | The container needs `/usr/sbin/sshd` and `xauth`, and the remote user needs a home directory. A `Deprecated option UsePrivilegeSeparation` warning from OpenSSH 7.5+ is harmless. |
| `vcp` hangs or says `subsystem request failed` | OpenSSH 9+ scp uses SFTP by default. Use `scp -O -S vsh`. |
| Pipes or redirections run locally instead of remotely | Quote the whole command: `vsh ct 'a \| b'`. In LXC, wrap it in `sh -c`. |
| `*.conf` or other globs match the wrong files | Globs are expanded on the vsh-host before the command reaches the container, whatever you quote. Avoid globs or use a script inside the container. |
| `-o atct` stops at one target | That name is not in the statefile or DNS, or no vsh-host lists it. Without `-p`, unknown targets abort the run; denied ones do not. Add `-p` to report unknown targets and carry on. |
| `vsh -t` did not add a host key | `ssh-keyscan` ignores `~/.ssh/config` and `user@host` entries. Connect once by hand to accept the key. |
| `### Sorry. Entering LXC containers as a user not implemented` | Run-as users do not work with LXC. Use root for that container. |
| Migration fails | The source host's root needs passwordless SSH to the destination's root. Also check leftovers kept by `--keep-dst` / `--remove-area no`. |

## Known limitations

* **`list` is not access controlled.** Every key holder sees every
  container name on a host.
* **`*` under `[containers]` also covers arbitrary `ssh:` targets**, not
  just the ones in `proxy-clients`. See
  [VSHD-INI.md → What is not access controlled](VSHD-INI.md#what-is-not-access-controlled).
* **Globs in commands expand on the vsh-host**, not in the container. See
  [VSH.md → Run in a container](VSH.md#run-in-a-container).
* **The key-loaded check fails for keys made by OpenSSH 7.8 or later**,
  so vsh asks for the passphrase on every call and removes keys loaded
  with `-a`. See [VSH.md → Known problem](VSH.md#known-problem-the-key-is-never-seen-as-loaded)
  for a workaround.
* **No deny rules** in `vshd.ini`. You can only grant access
  ([upstream #7](https://github.com/yownas/vsh/issues/7)).
* **The authorization logic is shell code.** Assume that root on a vsh-host
  is reachable by anyone who has a key installed there. See
  [CONCEPTS.md → Security model](CONCEPTS.md#security-model).
* **Migration** is OpenVZ/Virtuozzo only. Live mode for Virtuozzo is left to
  `prlctl` defaults.
* **LXC:** no migration and no run-as users. Commands run without a shell.
* **Solaris:** no migration. Permission names are the zone names.
* **FreeBSD:** the backend is a stub. Only `hostrun` and modules work, and
  its `list` output shows up in `vsh -l` as a bogus container called `NOT`.
* **`vsh:` proxying** is experimental and interactive only. See
  [PROXY-CLIENTS.md](PROXY-CLIENTS.md#chaining-vsh-vsh).
* **Duplicate names** across hosts, or proxy aliases defined on several
  hosts, are ambiguous. The client can even mix the host of one match with
  the id of another. The statefile is matched with plain text searches,
  see [upstream #3](https://github.com/yownas/vsh/issues/3).
* **Install path:** `/opt/vsh/bin/vshd` is hard-coded in the keys generated
  by `vsh -g`. If you install elsewhere, edit the `.dist.pub` files.
* **`qc` module** works on OpenVZ only.
* **Paths with spaces** in commands, file copies and statefile entries are
  not handled reliably. Arguments are word-split several times on the way
  ([upstream #14](https://github.com/yownas/vsh/issues/14) covered `vcp`).
