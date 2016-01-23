```
VSH daemon

Usage: /opt/vsh/bin/vshd ...

Actions:

From vsh:
  hostrun [<command>]
    Run command on local host.

  list
    Show list of all containers.

  module <modulename> [<args>]

  move <ct> <host>
  move-offline <ct> <host>
    Move container to another host.

  moveall <host> [<host>]
  moveall-offline <host> [<host>]
    Move all containers to other hosts.

  run <ct> [<command>]
    Run command in container.

  start <ct>
  stop <ct>
    Start or stop a container.
```

vshd expect an argument (user=<username>) with the user that is running it. Actions is sent via $SSH_ORIGINAL_COMMAND.

All this is done by the sshd on the server, username set from ~/.ssh/authorized_keys and $SSH_ORIGINAL_COMMAND is what the vsh-client is trying to send as command. If you have setup vshd properly you don't need to worry about any of these things.
