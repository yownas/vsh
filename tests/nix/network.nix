# Network services: dnsmasq (on vshhost1) answering for vsh.test, and the
# plain SSH host "target" used as a proxy client.
{
  dns =
    { lib, nodes, ... }:
    let
      ip = n: nodes.${n}.networking.primaryIPAddress;
      containersOf = n: nodes.${n}.vsh-test.containers or [ ];
      # Containers resolve to the vsh-host they live on. host-record (unlike
      # address=) answers AAAA/MX with NODATA instead of NXDOMAIN, as a
      # real zone would; vsh's parsing of `host` output depends on that.
      records = lib.concatMap (n: map (ct: "${ct},${ip n}") (containersOf n)) (builtins.attrNames nodes);
    in
    {
      services.dnsmasq = {
        enable = true;
        resolveLocalQueries = false;
        settings = {
          no-resolv = true;
          domain = "vsh.test";
          local = "/vsh.test/";
          expand-hosts = true;
          host-record = records;
        };
      };
      networking.firewall.allowedUDPPorts = [ 53 ];
      networking.firewall.allowedTCPPorts = [ 53 ];
    };

  target =
    { keys, ... }:
    {
      imports = [ ./common.nix ];
      services.openssh = {
        enable = true;
        ports = [
          22
          2222
        ];
        settings.PermitRootLogin = "prohibit-password";
        # Lets a test tell which port a proxied connection used.
        extraConfig = ''
          Match LocalPort 2222
            SetEnv VSH_TEST_PORT=2222
        '';
      };
      users.users.root.openssh.authorizedKeys.keyFiles = [ "${keys}/vshhost2-root.pub" ];
    };

  # vshhost2 connects to target as root with its own key.
  proxyHost =
    { keys, ... }:
    {
      system.activationScripts.vshProxyKey = ''
        install -d -m700 /root/.ssh
        install -m600 ${keys}/vshhost2-root /root/.ssh/id_ed25519
      '';
    };
}
