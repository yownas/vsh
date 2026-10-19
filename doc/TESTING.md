# Testing

The test suite lives in `tests/` and is driven by the Nix flake. It has three
tiers:

| Tier | What | Needs | Time |
| --- | --- | --- | --- |
| lint | shellcheck over all scripts (advisory) | Nix | seconds |
| unit | bats tests of `vsh` and `vshd` with stubbed backends | Nix (bwrap) | seconds |
| integration | NixOS VMs: a workstation, LXC vsh-hosts, a proxied SSH host | Nix, KVM | minutes |

## Running

Enter the dev shell, which prints the available commands:

```sh
nix develop
vsh-test unit          # against your working tree
vsh-test core          # integration: the main network
vsh-test all
```

Without the dev shell, run `tests/vsh-test <command>` directly. The script
uses the flake as `path:` so new files are picked up before you `git add`
them. Plain `nix flake check` works too, but only sees files git knows about.

## Unit tier

`tests/unit/*.bats`. `vshd` and `libexec/vshd-Linux` run unmodified inside
bubblewrap with `/opt/vsh` bind-mounted from a temporary directory and
`vshd.ini` from `tests/fixtures/`. Only the tools vshd calls (`lxc-*`,
`logger`, `ssh`) are stubs, which record their arguments in `$ROOT/log`.
The `vsh` client gets a temporary `$HOME` and a stub `ssh` that answers
`list` like two vsh-hosts would.

Run a subset with `vsh-test unit -f '<name regex>'`.

## Integration tier

`tests/integration/{core,onboarding}.nix` define the networks and
`*.py` the test scripts (NixOS test driver).

```
 ws ──▶ vshhost1  LXC web01.vsh.test, db01.vsh.test; dnsmasq for vsh.test
  │
  └──▶ vshhost2  LXC app01.vsh.test; proxy clients gw → target:22, gw2 → target:2222
                     └──▶ target (plain sshd)
```

Identities (see `tests/fixtures/vshd.ini`):

| User | Can |
| --- | --- |
| `alice` | everything except operations |
| `alice+admin` (`vsh -k admin`) | also start/stop/move |
| `bob` | only `db01.vsh.test` and `gw2`, no hostrun |
| `carol` | starts with nothing; the onboarding test runs `vsh -t` for her |

The pre-baked keys in `tests/nix/keys.nix` have no passphrase and are only
for tests. The onboarding test makes real, passphrase-protected keys and
answers the prompts with `expect`.

To poke around in the network:

```sh
vsh-test interactive core
>>> start_all()
>>> ws.succeed("su - alice -c 'vsh -l'")
>>> ws.shell_interact()     # shell on the workstation
>>> test_script()           # run the whole script
```

## Known bugs

Tests describe correct behaviour. Where vsh is currently wrong the test wraps
the check in `expect_known_bug KB-n ...` (bats) or
`expect_known_bug("KB-n", fn)` (Python). That test passes while the bug
exists and fails once it is fixed, so fixes cannot go unnoticed. Each `KB-n`
is described in [TODO.md](../TODO.md). `vsh-test known-bugs` lists where
each one is tested.

To add one: write the check for the correct behaviour as a function, wrap
it in `expect_known_bug` with the next free number, and add an entry to
TODO.md. The function must fail on the *behaviour*, not because the harness
broke. The bats helper refuses to count sandbox errors, and the Python
helper only counts failed `check()` calls.

## CI

`.github/workflows/test.yml` runs lint (advisory), unit and the two
integration tests as separate jobs on `ubuntu-latest`. The Nix store is
cached with `cache-nix-action`. Actions are pinned by commit SHA with the
tag in a comment.
