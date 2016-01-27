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

    -l

Simply list all containers on all hosts. (That you have access to.)

    [-r] <container> [<command>]

Run a command in the container or get a root-shell. (-r is not needed) Vsh will find and log into the correct host and then enter the container you specified.

    -x <container> [<command>]

Get a shell or run a command with X11 forwarding. Will run a second ssh tunneled through vsh to enable X11 forwarding and tty allocation (needed for screen and other commands).

    -h <container> [<command>]
    -H <host> [<command>]

Use this to get a shell or run a command on the vshd-host that contains the container or the specified host if you use -H. -H is basically a ssh to the host, but using vsh/vshd instead which enables some access control.

    -g [<suffix>]
    -k <suffix> -g

Generate a new key or show a key that is already generated. Use the suffix if you want to generate keys apart from the first 'user' key you generate. See the example ~/.vsh/vshd.ini above.

    -k <suffix> [<other options/commands>]
    
You can also use -k suffix or set VSH_KEY to select different roles. Default it to use your "user" key, but maybe you want to use an "admin" key to access the containers as root or separate "manager" key to start/stop or move containers.

With -k alone vsh will list the keys you have.

    -o <command>

This will run different operation command.

    -o move <container> <newhost>
    -o move-offline <container> <newhost>

(OpenVZ only.)
Move a container to a new host. Default is to try to move the container live without restarting it. If you need a restart because of enabled features, try the offline version.

    -o moveall <oldhost> <newhost1> [<newhost2> [<newhost3>]]
    -o moveall-offline <oldhost> <newhost1> [<newhost2> [<newhost3>]]

(OpenVZ only.)
Move all containers on oldhost to newhost1 (and newhost2 (and newhost3)) in a round-robin fashion. This could be used to empty a host if you need to do maintainance. (See move|move-offline for more information.)

    -o start <container>
    -o stop <container>

Start or stop the container. I leave it as a challenge to the reader to figure out which one does what.

    -o athosts <command>

Run command on all the hosts in your hosts-file. 

    -M <module> [<module-argument>]

Run scripts/modules that are helpful to vzsh but not so much that they should be a part of the core vsh-script.

    -u
    (Or set VSH_UPDATE to 0 or false)

For every command the script execute it will run ssh to all hosts in your ~/.vsh/hosts file and look for containers. Sometimes this can be a bit time-consuming, a host may be down or moving a dns-server-container causes trouble. Using -u will skip this part and assume that the state-file created last time is accurate.

    -q

Does some things a bit less verbose.

