# vsh
Vad Som Helst (vzsh without the Z)

A tool to manage containers that sometimes is good at managing root on other hosts.

Read doc/QUICKGUIDE for a quick start.

# Installation

Client:

* Copy vsh to /usr/bin (or other folder in $PATH)
* Add hosts to ~/.vsh/hosts
* Create keys with vsh -t

Server:

* Create /opt/vsh and copy required files:

```
bin/vshd
etc/vshd.ini
etc/proxy-clients (optional. skip this if you are not sure you actually need it)
libexec/vshd-*
modulesd/ (optional. Copy server-part of modules here if you have any)
```

* Put the keys from the client(s) called *.dist.pub in ~root/.ssh/authorized_keys
* Add your username to vshd.ini
* Add clients you want to ssh to via vshd in etc/proxy-clients (optional)

Good luck.
