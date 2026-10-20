{ pkgs, vsh }:
let
  keys = import ../nix/keys.nix { inherit pkgs; };
  network = import ../nix/network.nix;

  # Open a shell in a container through vsh, prove it is interactive and
  # inside the container, and leave.
  expectShell = pkgs.writeScript "vsh-expect-shell" ''
    #!${pkgs.expect}/bin/expect -f
    set timeout 30
    spawn vsh [lindex $argv 0]
    expect -re {[#$] $}
    send "test -t 0 && echo TTY-OK; cat /etc/vsh-ct-name\r"
    expect "TTY-OK" { } timeout { exit 1 }
    expect [lindex $argv 0] { } timeout { exit 1 }
    send "exit\r"
    expect eof
  '';
in
pkgs.testers.runNixOSTest {
  name = "vsh-integration-core";

  node.specialArgs = { inherit vsh keys; };

  nodes = {
    ws = {
      imports = [ ../nix/workstation.nix ];
      vsh-test.users = [
        "alice"
        "bob"
      ];
      vsh-test.hosts = [
        "vshhost1"
        "vshhost2"
      ];
    };

    vshhost1 = {
      imports = [
        ../nix/vshd-host.nix
        ../nix/lxc.nix
        network.dns
      ];
      vsh-test.containers = [
        "web01.vsh.test"
        "db01.vsh.test"
      ];
    };

    vshhost2 = {
      imports = [
        ../nix/vshd-host.nix
        ../nix/lxc.nix
        network.proxyHost
      ];
      vsh-test.containers = [ "app01.vsh.test" ];
      vsh-test.proxyClients = true;
    };

    target = network.target;
  };

  testScript = ''
    EXPECT_SHELL = "${expectShell}"
  ''
  + builtins.readFile ./common.py
  + builtins.readFile ./core.py;
}
