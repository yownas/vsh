This doccument is for examples and general usage. For more indepth explaination look at INSTALL.md, VSH.md or VSHD.md.

# User setup #

If vsh and vshd are installed correctly, as a user you still need to set up your vsh-keys and get a hostfile to use.

To generate your first user-key and set up template folders run `vsh -t` and follow the instructions.

```
$ vsh -t
/home/myuser/.vsh/hosts created.

Please add vsh-hosts to this file.

ctstate-folder exist. Skipping.
Creating default keys:
Enter passphrase (empty for no passphrase): 
Enter same passphrase again: 
/home/myuser/.vsh/keys/vsh-myuser-user generated

Distribute this to ~root/.ssh/authorized_keys on all vsh-hosts:

command="/opt/vsh/bin/vshd user=myuser" ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDY4XdhM4DWbmjHWsLOj9R+Vpw1/KmSjpA8oF0GdcHUFb1POo4Vz0oJIlOxHYI3t8ZzEuj9fl43uzh7jAWxn0T2ETvo5jZSjCooDNNxDwqxa43C14q7aZqRRYHOA46QiF+mCzfseOEQxmmbS6mbPg7wq1A+bVboIq/qgw4VCsdOUxhWDA8WbP4mGcfZcLwI7xK4HWQBTppZKlD+s/O/1U02U+QrgAphnRokJOM0+wGNrIcqa9+gz4BYtr9TXOCc8uY4RSfBWdXjLFUXNP1kS3queAeyN2u6+3Ny/gXgA7aqEszAPkxCu61z43jx0A78hgylcFrnBD3hNSpL6tHJ74Rv vsh-myuser-user
```

The "random" text at the end is the public part of your key and you should give this to your administrator to copy it to all vsh-hosts. If you need the file you can copy all the files in `~/.vsh/keys/` that end with `.dist.pub` and distribute them.

When the key is added you need a list of vshd-hosts to put in your `~/.vsh/hosts` (one server per line).

If your hostfile exist or one has been setup and referenced with VSH_HOSTFILE the ssh hostkeys will be added to your ~/.ssh/known_hosts file.

After you added the hosts you should be able to list all available containers with `vsh -l`.

# Using ssh-agent #

vsh tries to make it easy to use passwords with your generated keys. If you don't have ssh-agent running it will start one temporarily. To avoid having to type your password every time you use vsh you can use ssh-add to add the key to ssh-agent and set a time-out for how it should be valid.

If you need to start a ssh-agent in your current shell you can type: `eval `ssh-agent``

If you want to keep you key loaded in ssh-agent you can add the key you use with: `vsh -k keyname -a <other commands>`.

