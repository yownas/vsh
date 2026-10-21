{
  description = "vsh - test suite (lint, unit, NixOS VM integration)";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";

  outputs =
    { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
      lib = nixpkgs.lib;

      # The scripts exactly as they are in the working tree. Shebangs are left
      # untouched on purpose: vsh-hosts provide /bin/bash like a real system.
      vsh = pkgs.stdenvNoCC.mkDerivation {
        pname = "vsh";
        version = "0-test";
        src = lib.fileset.toSource {
          root = ./.;
          fileset = lib.fileset.unions [
            ./vsh
            ./vshd
            ./libexec
            ./etc
            ./modules
            ./modulesd
            ./contrib
          ];
        };
        dontPatchShebangs = true;
        installPhase = ''
          mkdir -p $out/bin $out/share/bash-completion/completions
          install -m755 vsh vshd $out/bin/
          install -m755 contrib/vsh-agent contrib/vcp contrib/vshcopy $out/bin/
          cp contrib/vsh-complete.bash $out/share/bash-completion/completions/vsh
          cp -r libexec etc modules modulesd $out/
        '';
      };

      unitDeps = with pkgs; [
        bash
        bats
        bubblewrap
        coreutils
        findutils
        gawk
        gnugrep
        gnused
        hostname
        util-linux
      ];

      testArgs = { inherit pkgs vsh; };
    in
    {
      packages.${system} = {
        inherit vsh;
        default = vsh;
      };

      checks.${system} = {
        # Advisory: always builds and writes the findings to $out. CI and
        # `vsh-test lint` fail when the report is non-empty.
        shellcheck =
          pkgs.runCommand "vsh-shellcheck"
            {
              nativeBuildInputs = [ pkgs.shellcheck ];
              src = vsh;
            }
            ''
              cd $src
              shellcheck -x -s bash bin/vsh bin/vshd libexec/vshd-Linux \
                bin/vsh-agent bin/vcp bin/vshcopy \
                modules/* modulesd/* > $out 2>&1 || true
            '';

        unit =
          pkgs.runCommand "vsh-unit"
            {
              nativeBuildInputs = unitDeps ++ [ pkgs.openssh ];
              src = ./tests;
            }
            ''
              export VSH_PKG=${vsh}
              bats --print-output-on-failure $src/unit 2>&1 | tee $out
              exit ''${PIPESTATUS[0]}
            '';

        integration-core = import ./tests/integration/core.nix testArgs;
        integration-onboarding = import ./tests/integration/onboarding.nix testArgs;
      };

      apps.${system} = {
        # Unit tier outside the Nix sandbox, in case bwrap is not allowed in it.
        unit = {
          type = "app";
          program = toString (
            pkgs.writeShellScript "vsh-unit" ''
              export PATH=${lib.makeBinPath (unitDeps ++ [ pkgs.openssh ])}:$PATH
              export VSH_PKG=${vsh}
              exec bats --print-output-on-failure ${./tests}/unit "$@"
            ''
          );
        };

        # RPM and deb packages from the working tree, see packaging/build. Runs
        # outside the sandbox because the version comes from `git describe`.
        packages = {
          type = "app";
          program = toString (
            pkgs.writeShellScript "vsh-build-packages" ''
              export PATH=${
                lib.makeBinPath [
                  pkgs.nfpm
                  pkgs.gitMinimal
                  pkgs.coreutils
                ]
              }:$PATH
              exec ${pkgs.bash}/bin/bash ${./packaging/build} "$@"
            ''
          );
        };
      };

      # Unit tests in the dev shell run against the working tree (no VSH_PKG).
      devShells.${system}.default = pkgs.mkShell {
        packages = unitDeps ++ [
          pkgs.openssh
          pkgs.shellcheck
          pkgs.nixfmt
          pkgs.nfpm
        ];
        shellHook = ''
          export PATH=$PWD/tests:$PATH
          # Enable .githooks/ (pre-push runs the unit tier), unless the
          # clone already uses other hooks.
          git config core.hooksPath > /dev/null 2>&1 ||
            git config core.hooksPath .githooks 2> /dev/null || true
          vsh-test help
        '';
      };

      formatter.${system} = pkgs.nixfmt;
    };
}
