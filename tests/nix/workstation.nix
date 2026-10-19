# The admin workstation: vsh on PATH and one Unix user per test identity.
#
# Users in vsh-test.users get the pre-baked keys and a ~/.vsh/hosts listing
# vsh-test.hosts. Users in vsh-test.freshUsers get nothing, like a new admin.
{
  config,
  lib,
  pkgs,
  vsh,
  keys,
  ...
}:
let
  cfg = config.vsh-test;
  keyNames = {
    alice = [
      "user"
      "admin"
    ];
    bob = [ "user" ];
  };
  setupUser = u: ''
    h=/home/${u}
    install -d -o ${u} -m700 $h/.vsh $h/.vsh/keys $h/.vsh/var $h/.vsh/modules
    printf '%s\n' ${lib.escapeShellArgs cfg.hosts} > $h/.vsh/hosts
    cp ${vsh}/modules/* $h/.vsh/modules/
    ${lib.concatMapStrings (k: ''
      install -m600 ${keys}/vsh-${u}-${k} $h/.vsh/keys/
      install -m644 ${keys}/vsh-${u}-${k}.pub ${keys}/vsh-${u}-${k}.dist.pub $h/.vsh/keys/
    '') keyNames.${u}}
    chown -R ${u}: $h/.vsh
  '';
in
{
  imports = [ ./common.nix ];

  options.vsh-test = {
    users = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
    };
    freshUsers = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
    };
    hosts = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
    };
  };

  config = {
    users.users = lib.genAttrs (cfg.users ++ cfg.freshUsers) (_: {
      isNormalUser = true;
    });

    system.activationScripts.vshUsers = {
      deps = [ "users" ];
      text = lib.concatMapStrings setupUser cfg.users;
    };

    environment.systemPackages = [
      vsh
      pkgs.dnsutils # `host`, used by vsh for DNS lookups
      pkgs.expect
      pkgs.procps
    ];
  };
}
