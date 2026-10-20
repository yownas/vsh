# A vsh-host: sshd with /opt/vsh installed as in doc/INSTALL.md, the user
# keys in ~root/.ssh/authorized_keys and vshd logging to journald.
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
in
{
  imports = [ ./common.nix ];

  options.vsh-test.proxyClients = lib.mkEnableOption "the proxy-clients fixture";

  config = {
    services.openssh = {
      enable = true;
      settings = {
        PermitRootLogin = "prohibit-password";
        # Tests make deliberately failing logins; OpenSSH >= 9.8 would then
        # drop the workstation's next connections for a while.
        PerSourcePenalties = "no";
      };
    };

    # vshd uses #!/bin/bash and /bin/bash -il, like any non-NixOS host has.
    # Installed as in doc/INSTALL.md: /opt/vsh/{bin,libexec,modulesd,etc}.
    systemd.tmpfiles.rules = [
      "L+ /bin/bash - - - - ${pkgs.bashInteractive}/bin/bash"
      "d /opt/vsh 0755 root root -"
      "d /opt/vsh/etc 0755 root root -"
      "L+ /opt/vsh/bin - - - - ${vsh}/bin"
      "L+ /opt/vsh/libexec - - - - ${vsh}/libexec"
      "L+ /opt/vsh/modulesd - - - - ${vsh}/modulesd"
      "L+ /opt/vsh/etc/vshd.ini - - - - ${../fixtures/vshd.ini}"
    ]
    ++ lib.optional cfg.proxyClients "L+ /opt/vsh/etc/proxy-clients - - - - ${../fixtures/proxy-clients}";

    # A real, writable ~root/.ssh/authorized_keys so the onboarding test can
    # install a new key the way an admin would.
    system.activationScripts.vshAuthorizedKeys = ''
      install -d -m700 /root/.ssh
      cat ${keys}/vsh-*.dist.pub > /root/.ssh/authorized_keys
      chmod 600 /root/.ssh/authorized_keys
    '';

    environment.systemPackages = with pkgs; [
      gawk
      gnugrep
      gnused
      hostname
      util-linux
    ];
  };
}
