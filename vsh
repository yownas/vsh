#!/bin/sh

############################
# Variables
############################

hostfile=~/.vsh/hosts
keyfile_name=~/.vsh/keys/vsh-`whoami`-SUFFIX
statefile=~/.vsh/ctstate
modules=~/.vsh/modules

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
    if [  "$prefix" = "true" -a "$cmd" = "hostrun" ];
    then
      $SSH -o LogLevel=QUIET $vshhost $cmd $ccmd | sed "s/^/$vshhost /"
    else
      $SSH -o LogLevel=QUIET $vshhost $cmd $ccmd
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
    vsh_container=`getent hosts $ct | awk '{print $2}'`
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

# vsh_updatestate
# Update containers and their state from all hosts
vsh_updatestate() {
  [ -f "$statefile" ] && rm -f $statefile
  touch $statefile

  # Parallelize all the things on all the hosts.
  for tmp_vshhost in $vsh_hosts;
  do
    echo "" | $SSH -o LogLevel=QUIET $tmp_vshhost list 2> /dev/null > ${statefile}_${tmp_vshhost} &
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
	-k <suffix>
		Select key to use.
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
update=true
[ "$VZSHUPDATE" = "0" -o "$VZSH_UPDATE" = "false" ] && update=false
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
          echo "ERROR: hostname needed."
          exit 1
        fi
        break;;
      -k)
        shift;
        keysuffix=$1;
        shift;;
      -l)
        action=list;
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
[ -z "$keysuffix" ] && keysuffix=$VZSH_KEY 
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
  fi
fi

# Set ssh-command to use now when we know which key to use.
#SSH="ssh -l root -t -o PasswordAuthentication=no -o ConnectTimeout=3 -o LogLevel=QUIET -i $keyfile"
SSH="ssh -l root -t -o PasswordAuthentication=no -o ConnectTimeout=3 -i $keyfile"

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

  if [ \! -s "$keyfile" -o \! -s "${keyfile}.pub" ]
  then
    usage
    echo ""
    echo "ERROR: $keyfile or ${keyfile}.pub missing or empty."
    echo "Generate key-pair with: $0 -g"
    exit 1
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
    ssh-keygen -q -t rsa -C `echo $keyfile | sed 's#^.*/##'` -f $keyfile && (

      # Unless this is the X11-key, create dist-key-file
      if [ \! "$keysuffix" = "X11" ]; then
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
    )
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
      $SSH $vshhost hostrun $ccmd
    else
      echo "hostrun: Container host not found."
      exit 1
    fi
    ;;
  list)
    [ "$update" = "true" ] && vsh_updatestate
    cat $statefile
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
          $SSH $vshhost $ccmd $ct $otherhosts
        else
          echo "operation: Container host not found for $ct."
          exit 1
        fi
        break;;
      moveall|moveall-offline)
        vshhost=$ct
        $SSH $vshhost $ccmd $otherhosts
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
    vsh_getctname $ct
    ct=$vsh_return
    vsh_gethost $ct
    vshhost=$vsh_return
    if [ ! "$vshhost" = "" ]
    then
      $SSH $vshhost run $ct $ccmd
    else
      echo "run: Container host not found."
      exit 1
    fi
    ;;
  template)
    # Check if config exists, otherwise create a new one.
    tmp_dir="`echo $hostfile | sed 's#/[^/]*$##'`"
    if [ \! -d "$tmp_dir" ]
    then
      mkdir -p "$tmp_dir"
      touch $hostfile
      cat <<EOF
$0: $tmp_dir & $hostfile created.

IMPORTANT! You need to add OpenVZ hosts to this file.

EOF
    fi
    # Generate X11-keys
    $0 -q -g X11
    # Generate user-keys
    $0 -g user
    ;;
  usage)
    usage
    exit
    ;;
  xrun)
    [ "$update" = "true" ] && vsh_updatestate
    vsh_getctname $ct
    ct=$vsh_return
    vsh_gethost $ct
    vshhost=$vsh_return
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
      gecos=`$SSH $vshhost run $ct 'getent passwd \`whoami\`'`

      remote_user=`echo $gecos|cut -d: -f 1`
      remote_home=`echo $gecos|cut -d: -f 6`

      # Create folder and copy temporary host-key
      cat ${xkey} | $SSH -o LogLevel=QUIET $vshhost run $ct "(mkdir ${remote_home}/.vsh 2>/dev/null);cat > ${remote_home}/.vsh/x11.tmp$$"

      # Write X11-keys, start remote sshd and connect using a dummy name.
      ssh -i ${xkey} -XY -o LogLevel=QUIET -o StrictHostKeyChecking=no -o VerifyHostKeyDNS=no -o EnableSSHKeysign=no -o HostbasedAuthentication=yes -o UserKnownHostsFile=/home/yes/.vsh/host-yes-X11 -o "ProxyCommand $SSH $vshhost run $ct \"chmod 700 ${remote_home}/.vsh;(echo `tr -d '\012' < ${xkey}.pub` > ${remote_home}/.vsh/x11.tmp$$.pub);chmod 600 ${remote_home}/.vsh/x11.tmp$$*;/usr/sbin/sshd -i -o HostbasedAuthentication=yes -o HostKey=${remote_home}/.vsh/x11.tmp$$ -o AuthorizedKeysFile=${remote_home}/.vsh/x11.tmp$$.pub -o UsePrivilegeSeparation=no -o UsePAM=no;rm ${remote_home}/.vsh/x11.tmp$$.pub ${remote_home}/.vsh/x11.tmp$$\"" -l $remote_user vsh-x11-connection $ccmd

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




