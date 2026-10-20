# Real LXC containers on a vsh-host.
#
# Each container gets a tiny rootfs: /nix/store bind-mounted read-only, a
# /bin with bash and coreutils, and /etc/vsh-ct-name so tests can tell which
# container a command actually ran in.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.vsh-test;

  ctEnv = pkgs.buildEnv {
    name = "vsh-test-ct-env";
    paths = with pkgs; [
      bashInteractive
      coreutils
      gnugrep
      hostname
      procps
    ];
  };

  # PID 1 that exits cleanly on lxc-stop.
  init = pkgs.writeText "vsh-test-ct-init" ''
    trap 'exit 0' TERM PWR INT
    while :; do sleep 1 & wait $!; done
  '';

  mkContainer = name: ''
    d=/var/lib/lxc/${name}
    if [ ! -e $d/config ]; then
      mkdir -p $d/rootfs/{etc,proc,sys,dev,tmp,root,nix/store,usr,run/current-system/sw}
      # lxc-attach keeps the host's PATH, so make that resolve as well.
      for p in bin usr/bin run/current-system/sw/bin; do ln -s ${ctEnv}/bin $d/rootfs/$p; done
      echo ${name} > $d/rootfs/etc/vsh-ct-name
      echo "root:x:0:0:root:/root:/bin/bash" > $d/rootfs/etc/passwd
      echo "root:x:0:" > $d/rootfs/etc/group
      cat > $d/config <<EOF
    lxc.uts.name = ${name}
    lxc.rootfs.path = dir:$d/rootfs
    lxc.mount.entry = /nix/store nix/store none bind,ro 0 0
    lxc.mount.auto = proc:mixed sys:ro cgroup:mixed
    lxc.autodev = 1
    lxc.net.0.type = empty
    lxc.init.cmd = /bin/bash ${init}
    lxc.signal.halt = SIGTERM
    lxc.environment = PATH=/bin
    EOF
    fi
    lxc-info -n ${name} -s | grep -q RUNNING || lxc-start -n ${name}
  '';
in
{
  options.vsh-test.containers = lib.mkOption {
    type = lib.types.listOf lib.types.str;
    default = [ ];
    description = "LXC containers to create and start on this host.";
  };

  config = lib.mkIf (cfg.containers != [ ]) {
    virtualisation.lxc.enable = true;

    systemd.services.vsh-test-containers = {
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];
      path = [ config.virtualisation.lxc.package ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        Delegate = true;
        KillMode = "process";
      };
      script = lib.concatMapStrings mkContainer cfg.containers;
    };
  };
}
