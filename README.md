# vsh
Vad Som Helst (vzsh without the Z)

# Installation

Client:

* Copy vsh to /usr/bin (or other folder in $PATH)
* Add hosts to .vsh/hosts
* Create keys with vsh -t

Server:

* Create /opt/vsh and place vshd, etc/ and libexec/ there.
* Put the keys from the client called *.dist.pub in ~root/.ssh/authorized_keys
* Add your username to vshd.ini

Good luck.
