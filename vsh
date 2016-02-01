#!/bin/sh

############################
# Variables
############################

hostfile=~/.vsh/hosts
keyfile_name=~/.vsh/keys/vsh-`whoami`-SUFFIX
statefile=~/.vsh/var/ctstate
modules=~/.vsh/modules

SSH="ssh -t -o PasswordAuthentication=no -o ConnectTimeout=4"

############################
# Variables (Do not edit)
############################

vsh_hosts=`cat $hostfile 2> /dev/null| awk '/^[^#]/{print $1}' | tr '\012' ' ' `

############################
# Functions
############################

# vsh_athosts cmd
# Run command on all the hosts.
vsh_athosts() {
  cmd=$1
  shift
  ccmd=$*
  for vshhost in $vsh_hosts;
  do
    if [ "$prefix" = "true" -a "$cmd" = "hostrun" ];
    then
      VSH_SSH_OPTS="-o LogLevel=QUIET"
      vsh_ssh $vshhost $cmd $ccmd | sed "s/^/$vshhost /"
    else
      VSH_SSH_OPTS="-o LogLevel=QUIET"
      vsh_ssh $vshhost $cmd $ccmd
    fi
  done
}

# vsh_getctname ct
# Get fqdn or cid for container from dns or statefile
vsh_getctname() {
  ct=$1
  # fqdn/cid?
  vsh_container=`grep " $ct " $statefile | awk '{print $2}'`

  # Try to find container name.
  if [ "$vsh_container" = "" ]; then
    vsh_container=`host $ct | awk '{print $1}'`
  fi

  if [ "$vsh_container" = "" ]; then
    echo "getctname: Can not find container $ct"
    exit 1
  fi

  vsh_return=$vsh_container
}

# vsh_gethost ct
# Get host for container
vsh_gethost() {
  ct=$1
  vsh_getctname $ct
  cid=$vsh_return
  vsh_return=`cat $statefile | awk '{print $2" "$1" "$3}' | grep "^$cid " | cut -d" " -f2`
}

# vsh_getctpath ct
# Get path for container
vsh_getctpath() {
  tmp_ct=$1
  vsh_return=`cat $statefile | awk '{print $2" "$1" "$3}' | grep "^$tmp_ct " | head -1 | cut -d" " -f3`
  # If it isn't found as hostname, try as path
  if [ "$vsh_return" = "" ]
  then
    vsh_return=`cat $statefile | awk '{print $2" "$1" "$3}' | grep " $ct$" | head -1 | cut -d" " -f3`
  fi
}

# vsh_ssh [user@]host cmd
# ssh to vshd-hosts
vsh_ssh() {
  tmp_vsh_sshhost=$1
  shift
  tmp_cmd=$*

  # Set root as default user if none is set
  tmp_vsh_sshhost=`echo $tmp_vsh_sshhost | sed 's/^\([^@]*\)$/root@\1/'`

  $SSH $VSH_SSH_OPTS $tmp_vsh_sshhost $tmp_cmd 
  VSH_SSH_OPTS=""
}

# vsh_updatestate
# Update containers and their state from all hosts
vsh_updatestate() {
  rm -f $statefile ${statefile}_*
  touch $statefile

  # Parallelize all the things on all the hosts.
  for tmp_vshhost in $vsh_hosts;
  do
    VSH_SSH_OPTS="-o LogLevel=QUIET"
    echo "" | vsh_ssh $tmp_vshhost list 2> /dev/null > ${statefile}_${tmp_vshhost} &
  done
  wait
  cat ${statefile}_* | tr '\t' ' ' > $statefile
}

# usage
# Print usage
usage() {
	cat <<EOF
VZ shell

Usage: $0 [options] [action]

Options:
	-a
		Add used key to ssh-agent if possible.
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
	-ll
	-lll
		Show list of all containers on all hosts.
		List, list long, list longer
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
		distribute your ${keyfile}.dist.pub
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
EOF
}

############################
# Main
############################

# Defaults
action=run
addkey=false
update=true
[ "$VSHUPDATE" = "0" -o "$VSH_UPDATE" = "false" ] && update=false
prefix=false
quiet=false
# If needconf is set to yes we do need config-files.
needconf=yes

if [ -z "$1" ]
then
  action=usage
  needconf=no
else
  while [ \! -z "$*" ]; do
    case "$1" in
      -a)
        addkey="true";
        shift;
        ;;
      -g)
        action=genkeys;
        shift;
        [ -z "$keysuffix" ] && keysuffix=$1;
        needconf=no;
        break;;
      -h)
        action=hostrun;
        shift;
        ct=$1;
        shift;
        ccmd=$*;
        if [ -z "$ct" ]; then
          echo "ERROR: container name needed."
          exit 1
        fi
        break;;
      -H)
        action=hostrun;
        shift;
        vshhost=$1;
        shift;
        ccmd=$*;
        if [ -z "$vshhost" ]; then
          # No host given, list hosts.
          cat $hostfile | awk '{print $1}'
          exit 0
        fi
        break;;
      -k)
        shift;
        keysuffix=$1;
        if [ -z "$keysuffix" ]; then
          action=keylist
          needconf=no
          break
        fi
        shift;;
      -l|-ll|-lll)
        action=list;
        case "$1" in
          -l) ccmd="1";;
          -ll) ccmd="2";;
          -lll) ccmd="3";;
        esac
        shift;;
      -M)
        action=module;
        shift;
        ccmd=$1;
        shift;
        args=$*;
        if [ -z "$ccmd" ]; then
          echo "ERROR: module name needed."
          exit 1
        fi
        break;;
      -o)
        action=operation;
        shift;
        ccmd=$1;
        shift;
        ct=$1;
        shift;
        otherhosts=$*;
        if [ -z "$ccmd" ]; then
          echo "ERROR: operation needed."
          exit 1
        fi
        break;;
      -p)
        prefix=true;
        shift;;
      -q)
        quiet=true;
        shift;;
      -r)
        action=run;
        shift;
        ct=$1;
        shift;
        ccmd=$*;
        if [ -z "$ct" ]; then
          echo "ERROR: container name needed."
          exit 1
        fi
        break;;
      -t)
        action=template;
        needconf=no;
        break;;
      -u)
        update=false;
        shift;;
      -x)
        action=xrun;
        shift;
        ct=$1;
        shift;
        ccmd=$*;
        if [ -z "$ct" ]; then
          echo "ERROR: container name needed."
          exit 1
        fi
        break;;

      # Anything starting with - here is an error. Show usage.
      -\?|-*)
        action=usage;
        needconf=no;
        break;;

      # If no (more) options, treat the rest as <container> [<command>]
      *)
        ct=$1;
        shift;
        ccmd=$*;
        break;;
    esac
  done
fi

# Set key suffix from ENV or use default if none is given.
[ -z "$keysuffix" ] && keysuffix=$VSH_KEY 
[ -z "$keysuffix" ] && keysuffix=user 
keyfile=`echo $keyfile_name | sed "s/SUFFIX/${keysuffix}/"`

if [ "$needconf" = "yes" ]
then
  # Start a local ssh-agent if needed
  # Test if we can reach ssh-agent
  ssh-add -l > /dev/null 2>&1 
  vsh_result=$?
  if [ "$vsh_result" = "0" -o "$vsh_result" = "1" ]
  then
    vsh_tmpagent=no
    # Add key to external ssh-agent
    if [ "$addkey" = "true" ]
    then
      # FIXME: Maybe we should have a timeout here?
      ssh-add $keyfile 2> /dev/null
    fi
  else
    vsh_tmpagent=yes
    eval `ssh-agent -s` > /dev/null
  fi

  # Add key to ssh-agent
  if (ssh-add -L | grep $keyfile > /dev/null)
  then
    vsh_tmpagentkey=no
  else
    vsh_tmpagentkey=yes
    # Add temporary key with a timeout of 30 seconds
    # should be more than enough.
    ssh-add -t 30 $keyfile 2> /dev/null
    # FIXME: It seems to be a problem here, if you pipe something
    # through vsh it will skip this step.
  fi
fi

# Set ssh-keyfile to use now when we know which key to use.
SSH="${SSH} -i $keyfile"

if [ "$needconf" = "yes" ]
then
  # Sanity checks
  if [ \! -s "$hostfile" ]
  then
    usage
    echo ""
    echo "ERROR: $hostfile missing or empty."
    exit 1
  fi

  # Make sure keyfiles exist
  if [ \! -s "$keyfile" -o \! -s "${keyfile}.pub" ]
  then
    usage
    echo ""
    echo "ERROR: $keyfile or ${keyfile}.pub missing or empty."
    echo "Generate key-pair with: $0 -g"
    exit 1
  fi

  # Do some checks for -r
  if [ "$action" = "run" ]
  then
    # Check that we have a container name
    if [ "$ct" = "" ]
    then
      usage
      echo ""
      echo "ERROR: container name needed."
      exit 1
    fi

    # If container is in hostlist, do a hostrun instead of run
    if (cat $hostfile | awk '{print $1}' | grep "^${ct}$" > /dev/null)
    then
        action=hostrun
        vshhost=$ct;
    fi
  fi
fi

case "$action" in
  genkeys)
    if [ -f "${keyfile}" -o -f "${keyfile}.pub" ]; then
      if [ "$quiet" = "false" ]; then
        echo "Keyfiles $keyfile or ${keyfile}.pub exists."
        echo "Remove if you want to generate a new one.."
        echo "Or distribute this one to hosts you need access to."
        echo ""
        cat ${keyfile}.dist.pub
        echo ""
      fi
      exit 1
    fi
    keyusername=`whoami`
    if [ \! "$keysuffix" = "user" ]
    then
      keyusername="${keyusername}+${keysuffix}"
    fi

    comment=`echo $keyfile | sed 's#^.*/##'`

    if [ "$keysuffix" = "X11" ]; then
      ssh-keygen -q -t rsa -C "$comment" -f $keyfile -N "" || exit $?
    else
      ssh-keygen -q -t rsa -C "$comment" -f $keyfile || exit $?
      cat ${keyfile}.pub | sed "s#^#command=\"/opt/vsh/bin/vshd user=${keyusername}\" #" > ${keyfile}.dist.pub
    fi


    if [ "$quiet" = "false" ]; then
      echo "$keyfile generated"
      echo ""
      echo "Distribute this to ~root/.ssh/authorized_keys on all vsh-hosts:"
      echo ""
      cat ${keyfile}.dist.pub
      echo ""
    fi
    ;;
  hostrun)
    [ "$update" = "true" ] && vsh_updatestate
    # If $vshhost wasn't set by -H, get the host from the container-name
    if [ "$vshhost" = "" ]
    then
      vsh_getctname $ct
      ct=$vsh_return
      vsh_gethost $ct
      vshhost=$vsh_return
    fi
    if [ ! "$vshhost" = "" ]
    then
      vsh_ssh $vshhost hostrun $ccmd
    else
      echo "hostrun: Container host not found."
      exit 1
    fi
    ;;

  keylist)
    echo "Keylist:"
    echo "--------"
    # List all dist-keys
    ls -1 `echo $keyfile_name | sed 's/SUFFIX/*/'`.dist.pub |\
      # Remove everything except SUFFIX (the name of the key)
      sed 's#'`echo $keyfile_name | sed s/SUFFIX//`'##;s/\.dist\.pub$//' |\
      # Sort
      sort
    ;;

  list)
    [ "$update" = "true" ] && vsh_updatestate
    case "$ccmd" in
      3)
        cat $statefile | awk '{printf("%s %30s %30s %s\n", $1, $2, $3, $4)}'
        ;;
      2)
        cat $statefile | awk '{printf("%s@%s\n", $2, $1)}'
        ;;
      1|*)
        cat $statefile | awk '{printf("%s\n", $2)}'
        ;;
    esac
    ;;
  operation)
    [ "$update" = "true" ] && vsh_updatestate
    case "$ccmd" in
      # move, start & stop have similar arguments.
      # Treat them all the same way.
      move|move-offline|start|stop)
        vsh_getctname $ct
        ct=$vsh_return
        vsh_gethost $ct
        vshhost=$vsh_return
        if [ ! "$vshhost" = "" ]
        then
          vsh_ssh $vshhost $ccmd $ct $otherhosts
        else
          echo "operation: Container host not found for $ct."
          exit 1
        fi
        break;;
      moveall|moveall-offline)
        vshhost=$ct
        vsh_ssh $vshhost $ccmd $otherhosts
        break;;
      athosts)
        # $ct & $otherhosts contain the command to run
        vsh_athosts hostrun $ct $otherhosts 
        ;;
      *)
        echo "operation: Unknown command: $ccmd"
        exit 1
        ;;
    esac
    ;;
  module)
    if [ -f "${modules}/${ccmd}" ]; then
      #${modules}/${ccmd} ${args}
      . ${modules}/${ccmd}
    else
      echo "No module: ${ccmd}"
      exit 1
    fi
    ;;
  run)
    [ "$update" = "true" ] && vsh_updatestate
    # Get host of container
    vsh_gethost $ct
    vshhost=$vsh_return
    if [ "$vshhost" = "" ]
    then
      # Try getctname to parse the name and search for host again
      vsh_getctname $ct
      ct=$vsh_return
      vsh_gethost $ct
      vshhost=$vsh_return
    fi
    if [ ! "$vshhost" = "" ]
    then
      vsh_getctpath $ct
      tmp_path=$vsh_return
      if [ "$tmp_path" = "" ]
      then
        vsh_getctname $ct
        ct=$vsh_return
        vsh_getctpath $ct
        tmp_path=$vsh_return
      fi
      
      # Hopefully we have a host and path here...
      vsh_ssh $vshhost run $tmp_path $ccmd
    else
      echo "run: Container host not found."
      exit 1
    fi
    ;;
  template)
    # Check if config exists, otherwise create a new one.
    if [ \! -f "$hostfile" ]
    then
      # Create folders
      mkdir -p `echo $hostfile | sed 's#/[^/]*$##'`
      touch $hostfile
      cat <<EOF
$hostfile created.

Please add vsh-hosts to this file.

EOF
    else
      echo "Hostfile exist. Skipping."
    fi

    # Check if ctstate dir exists, otherwise create a new one.
    tmp_dir=`echo $statefile | sed 's#/[^/]*$##'`
    if [ \! -d "$tmp_dir" ]
    then
      # Create folders
      mkdir -p $tmp_dir
    else
      echo "ctstate-folder exist. Skipping."
    fi

    # Check if key dir exists, otherwise create a new one.
    tmp_dir=`echo $keyfile_name | sed 's#/[^/]*$##'`
    if [ \! -d "$tmp_dir" ]
    then
      # Create folders
      mkdir -p $tmp_dir

      echo "Creating default keys:"
      # Generate X11-keys
      $0 -q -g X11
      # Generate user-keys
      $0 -g user
    else
      echo "User-keys exist. Skipping."
    fi 
    ;;
  usage)
    usage
    exit
    ;;
  xrun)
    [ "$update" = "true" ] && vsh_updatestate
    # Get host of container
    vsh_gethost $ct
    vshhost=$vsh_return
    if [ ! "$vshhost" = "" ]
    then
      # Try getctname to parse the name and search for host again
      vsh_getctname $ct
      ct=$vsh_return
      vsh_gethost $ct
      vshhost=$vsh_return
    fi

#    [ "$update" = "true" ] && vsh_updatestate
#    vsh_getctname $ct
#    ct=$vsh_return
#    vsh_gethost $ct
#    vshhost=$vsh_return

    if [ ! "$vshhost" = "" ]
    then
      # Find X11-key
      xkey=`echo $keyfile_name | sed "s/SUFFIX/X11/"`

      if [ \! -f "${xkey}" -o \! -f "${xkey}.pub" ]; then
        echo "Can not find X11-keys!"
        echo "Please generate a key-pair with:"
        echo "$0 -g X11"
        echo "(You do not need to distribute these keys.)"
        exit 1
      fi

      # Connect and find out paths and remote username.
      gecos=`vsh_ssh $vshhost run $ct 'getent passwd \`whoami\`'`

      remote_user=`echo $gecos|cut -d: -f 1`
      remote_home=`echo $gecos|cut -d: -f 6`

      # Create folder and copy temporary host-keys and set filepermissions
      VSH_SSH_OPTS="-o LogLevel=QUIET"
      cat ${xkey} | vsh_ssh $vshhost run $ct "(mkdir ${remote_home}/.vsh 2>/dev/null);chmod 700 ${remote_home}/.vsh;cat > ${remote_home}/.vsh/x11.tmp$$"

      VSH_SSH_OPTS="-o LogLevel=QUIET"
      cat ${xkey}.pub | vsh_ssh $vshhost run $ct "cat > ${remote_home}/.vsh/x11.tmp$$.pub;chmod 600 ${remote_home}/.vsh/*"

      # Set root as default user if none is set
      vshhost=`echo $vshhost | sed 's/^\([^@]*\)$/root@\1/'`

      # Start remote sshd and connect using a dummy name.
      ssh -i ${xkey} -XY -o StrictHostKeyChecking=no \
        -o VerifyHostKeyDNS=no -o EnableSSHKeysign=no \
        -o UserKnownHostsFile=/dev/null \
        -o ProxyCommand="$SSH $vshhost run $ct \"/usr/sbin/sshd -i \
          -o HostKey=${remote_home}/.vsh/x11.tmp$$ \
          -o AuthorizedKeysFile=${remote_home}/.vsh/x11.tmp$$.pub \
          -o UsePrivilegeSeparation=no -o UsePAM=no; \
          rm ${remote_home}/.vsh/x11.tmp$$.pub ${remote_home}/.vsh/x11.tmp$$\"" \
         -l $remote_user vsh-x11-connection $ccmd

    else
      echo "xrun: Container not found."
      exit 1
    fi
    ;;
esac

# Clean up temporary ssh-agent and keys.
if [ "$vsh_tmpagentkey" = "yes" ]
then
  ssh-add -d ${keyfile}.pub 2> /dev/null
fi
if [ "$vsh_tmpagent" = "yes" ]
then
  eval `ssh-agent -sk` > /dev/null
fi




