# Quickstart

This walk-through goes from nothing to a root shell. For the full details on
every step, see [INSTALL.md](INSTALL.md).

## Prerequisites

The example uses three Unix machines:

* **admin-workstation**: the machine an administrator works from.
* **vshd-host**: runs `vshd`. Ideally it sits in a DMZ or on an admin network.
* **client-machine**: any host you want root on.

They can all be the same machine if you only want to try vsh. The steps below
still refer to each machine by its role.

You need `bash`, `ssh`, `ssh-keygen`, `ssh-agent` and `awk` everywhere, plus
`host` (from bind-utils/dnsutils) on the workstation.

Get the code on the admin-workstation and the vshd-host:

```sh
cd ~
git clone https://github.com/yownas/vsh.git
```

## 1. Client installation and key generation

On the **admin-workstation**, as your regular user:

```sh
mkdir -p ~/bin
cp ~/vsh/vsh ~/bin/
export PATH=$PATH:~/bin        # vsh calls itself as "vsh", so it must be in $PATH

# Make sure ~/.ssh and known_hosts exist
mkdir -p ~/.ssh && chmod 700 ~/.ssh
touch ~/.ssh/known_hosts && chmod 600 ~/.ssh/known_hosts

# Create ~/.vsh, an empty hostfile and your keys.
# Pick a GOOD passphrase: this key is effectively your root password.
vsh -t
```

`vsh -t` ends by printing a line like this:

```
command="/opt/vsh/bin/vshd user=alice" ssh-rsa AAAA...  vsh-alice-user
```

You can print it again at any time with `vsh -g`.

## 2. vshd-host installation

On the **vshd-host**, as root:

```sh
mkdir -p /opt/vsh/{bin,etc,libexec,modulesd}
cp ~/vsh/vshd          /opt/vsh/bin/
cp ~/vsh/libexec/*     /opt/vsh/libexec/
chmod 755 /opt/vsh/bin/vshd /opt/vsh/libexec/*
cp ~/vsh/etc/vshd.ini  /opt/vsh/etc/

# Replace "your_username" with the user name from the command="..." line
vi /opt/vsh/etc/vshd.ini
```

The minimal `vshd.ini` gives the `wheel` group access to everything:

```ini
[groups]
wheel:alice

[containers]
*:@wheel

[hosts]
*:@wheel

[operations]
move:@wheel
startstop:@wheel

[modules]
*:@wheel
```

Paste the `command="..."` line from step 1 into `~root/.ssh/authorized_keys`,
prefixed with `restrict,pty,` so the key cannot be used for port
forwarding (see [INSTALL.md](INSTALL.md#3-install-user-keys)):

```
restrict,pty,command="/opt/vsh/bin/vshd user=alice" ssh-rsa AAAA...  vsh-alice-user
```

## 3. Connect

Back on the **admin-workstation**:

```sh
echo vshd-host.local.domain >> ~/.vsh/hosts

# Running -t again with a non-empty hostfile collects the hosts' SSH host keys
vsh -t

vsh -p -o athosts uptime     # run a command on every vsh-host
vsh -l                       # list containers
vsh vshd-host.local.domain   # root shell on the vsh-host
```

All OpenVZ/Virtuozzo containers, LXC containers or Solaris zones on the
vshd-host are now listed by `vsh -l`, and you can enter them with
`vsh <name>`.

## 4. Add a proxy client

To give root on an ordinary machine without a container runtime, let the
vshd-host SSH into it as root.

On the **vshd-host**, as root:

```sh
# Generate root's ssh key if there is none
[ -f ~/.ssh/id_rsa ] || ssh-keygen

# This should be the last time you need client-machine's root password
ssh-copy-id client-machine.local.domain

# <alias> ssh:<host>
echo "client-machine ssh:client-machine.local.domain" >> /opt/vsh/etc/proxy-clients
```

On the **admin-workstation**:

```sh
vsh -l                  # client-machine now appears, with status "proxy"
vsh client-machine      # root shell on client-machine
```

## Next steps

* Give other admins access and set up roles: [VSHD-INI.md](VSHD-INI.md)
* Day-to-day usage: [USAGE.md](USAGE.md)
* All client flags: [VSH.md](VSH.md)
