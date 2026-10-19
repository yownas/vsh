# Pre-baked keys for the integration tests.
#
# Passphrase-less on purpose: the onboarding test covers real, passphrase
# protected keys made by `vsh -t`. Never use these anywhere else.
{ pkgs }:
pkgs.runCommand "vsh-test-keys" { nativeBuildInputs = [ pkgs.openssh ]; } ''
  mkdir -p $out
  key() { ssh-keygen -q -t ed25519 -N "" -C "$2" -f "$out/$1"; }

  # User keys, named as `vsh -g <suffix>` names them, plus their .dist.pub
  # with the forced command baked in.
  dist() {
    key "$1" "$1"
    echo "command=\"/opt/vsh/bin/vshd user=$2\" $(cat "$out/$1.pub")" > "$out/$1.dist.pub"
  }
  dist vsh-alice-user alice
  dist vsh-alice-admin alice+admin
  dist vsh-bob-user bob

  # vshhost2 -> target for proxy clients
  key vshhost2-root root@vshhost2

  # Host keys, and a known_hosts covering them.
  for h in vshhost1 vshhost2 target; do
    key "host-$h" "$h"
    echo "$h,$h.vsh.test,[$h]:2222 $(cut -d' ' -f1-2 "$out/host-$h.pub")" >> "$out/known_hosts"
  done
''
