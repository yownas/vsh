```
VZ shell

Usage: /usr/bin/vsh [options] [action]

Options:
	-k <suffix>
		Select key to use.
		No suffix will show a list of keys.
        -p
		Show hostname as prefix when using -o athosts
	-u
		Do not update container states.
	-q
		Be quiet.

Actions:
	[-r] <container> [<command>]
		Run command/shell in container.
	-x <container> [<command>]
		Run command/shell in container with X11 forwarding.
	-l
		Show list of all containers on all hosts.
	-o move <container> <host>
	-o move-offline <container> <host>
		Move container to host.
	-o moveall <host1> <host2> [<host3>]
	-o moveall-offline <host1> <host2> [<host3>]
		Move all containers from host1 to host2 [and host3]
	-o start <container>
		 Start container
	-o stop <container>
		Stop container
        -o athosts <command>
                Run command on all hosts.
	-M <module> [<module-argument>]
		Run scripts in ~/.vsh/modules/
	-g [<suffix>]
		Generate ssh-keyspairs. After keys been generated
		distribute your /home/yes/.vsh/keys/vsh-yes-user.dist.pub
                to all vsh-hosts you need to access. Admin also has to
                update vshd.ini to give you persmissions.
	-t
		Create folder and empty hostfile-template, implies -g.
	-h <container> [<command>]
		Run command/shell on host of container.
	-H <host> [<command>]
		Run command/shell on host.
	-?
		Show this.
```
