{ pkgs, vsh }:
let
  keys = import ../nix/keys.nix { inherit pkgs; };
  network = import ../nix/network.nix;

  # vsh-expect <passphrase> <command...>
  # Runs a command on a pty, answering every passphrase prompt (ssh-keygen,
  # ssh-add) with <passphrase>. Exits with the command's status.
  vshExpect = pkgs.writeScript "vsh-expect" ''
    #!${pkgs.expect}/bin/expect -f
    set timeout 60
    set pass [lindex $argv 0]
    spawn {*}[lrange $argv 1 end]
    expect {
      -re {[Pp]assphrase[^\n]*: $} { send "$pass\r"; exp_continue }
      timeout { exit 124 }
      eof
    }
    lassign [wait] pid spawnid os_error value
    exit $value
  '';
in
pkgs.testers.runNixOSTest {
  name = "vsh-integration-onboarding";

  node.specialArgs = { inherit vsh keys; };

  nodes = {
    ws = {
      imports = [ ../nix/workstation.nix ];
      vsh-test.users = [ "alice" ];
      vsh-test.freshUsers = [ "carol" ];
      vsh-test.hosts = [ "vshhost1" ];
      # carol learns host keys through `vsh -t`, like a new admin would.
      vsh-test.globalKnownHosts = false;
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
  };

  testScript = ''
    VSH_EXPECT = "${vshExpect}"
  ''
  + builtins.readFile ./common.py
  + builtins.readFile ./onboarding.py;
}
