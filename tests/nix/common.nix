# Settings every node shares: fixed host keys, a shared known_hosts, and DNS
# from dnsmasq on vshhost1.
{
  config,
  lib,
  nodes,
  keys,
  ...
}:
let
  name = config.networking.hostName;
  hasHostKey = builtins.elem name [
    "vshhost1"
    "vshhost2"
    "target"
  ];
in
{
  options.vsh-test.globalKnownHosts = lib.mkOption {
    type = lib.types.bool;
    default = true;
    description = "Trust the pre-baked host keys system wide.";
  };

  config = {
    environment.etc = lib.mkIf hasHostKey {
      "ssh/ssh_host_ed25519_key" = {
        source = "${keys}/host-${name}";
        mode = "0600";
      };
      "ssh/ssh_host_ed25519_key.pub".source = "${keys}/host-${name}.pub";
    };
    services.openssh.hostKeys = [
      {
        path = "/etc/ssh/ssh_host_ed25519_key";
        type = "ed25519";
      }
    ];

    programs.ssh.knownHostsFiles = lib.mkIf config.vsh-test.globalKnownHosts [ "${keys}/known_hosts" ];

    networking.nameservers = [ nodes.vshhost1.networking.primaryIPAddress ];
    networking.search = [ "vsh.test" ];
  };
}
