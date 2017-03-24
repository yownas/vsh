# Quickstart #

## Prerequisite ##

For this example we need three Un*x machines.

* admin-workstation - Workstation or server that the administrators use.
* vshd-server - Host, preferably in a DMZ or admin network.
* client-machine - Any host/server/user-workstation.

These can all be the same machine if you just want to try vsh, but to make things easier to understand we will refer to the hosts by their role.

First: Clone the vsh git-repo or download a zip/tar file and unpack it.

```
cd ~
git clone https://github.com/yownas/vsh.git
```

## Client installation and key generation ##

```
# On the admin-workstation as a regular user.

cd ~
mkdir bin
cp ~/vsh/vsh ~/bin

export PATH=${PATH}:~/bin

# Make sure you have a .ssh folder and a known_hosts file
mkdir ~/.ssh
chmod 600 ~/.ssh
touch ~/.ssh/known_hosts
chmod 600 ~/.ssh/known_hosts

# Generate templates and your default user-key. Make sure to set
# a GOOD password, this will be your personal root-password.

vsh -t
```

We are done here, for now.

## Vsdh-server installation and key distribution ##


```
# On the vshd-host as root.

mkdir -p /opt/vsh/bin
mkdir -p /opt/vsh/etc
mkdir -p /opt/vsh/libexec

cp ~/vsh/vshd /opt/vsh/bin
cp ~/vsh/libexec/* /opt/vsh/libexec

# Create minimal vshd.ini
cat <<EOF > /opt/vsh/etc/vshd.ini
[groups]
wheel=YOUR_USERNAME_HERE

[containers]
*:@wheel

[hosts]
*:@wheel

[operations]
move:@wheel
startstop:@wheel

[modules]
*:@wheel
EOF

# Do not forget to set your username!
# (The one you have on the admin-workstation)
vi /opt/vsh/etc/vshd.ini

```

Copy the vsh-key from the user at the admin-workstation.

```
# On the admin-workstation as the regular user.

# Get the user key

vsh -g user
```

Paste it into ~root/.ssh/authorized_keys on the vshd-server.


```
# Add the vshd-host to your host-list
echo vshd-host.local.domain >> ~/.vsh/hosts

# Get ssh-keys from the hosts
vsh -t

# Try to connect and run a command
vsh -p -o athosts uptime

# Get a shell...
vsh vsh-host
```

## Add a proxy-client ##

Any OpenVZ, LXC, or Solaris-zone on the vshd-host should be available automatically.
To add a proxy-client we need to enable root-login from the vshd-host to the client-machine.

```
# On the vshd-host as root

# Generate ssh-keys for root, if you do not have any.
ssh-keygen

# Copy public key. This should be the last time you need
# the root password for the client-machine.
ssh-copy-id client-machine.local.domain

# Add the client-machine to the list of proxy-clients
# Entries should be added in the format:
# <host> ssh:<host>

touch /opt/vsh/etc/proxy-clients
echo "client-machine.local.domain ssh:client-machine.local.domain" >> /opt/vsh/etc/proxy-clients
```

```
# On the admin-workstation as regular user

# Try listing the proxied client
vsh -l

# Log in as root on client-machine
vsh client-machine
```
If everything works, you should have a root-shell on the client-machine now. :)
