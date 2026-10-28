{
  description = "Emacs package: org-roam-blog";

  inputs = {
    nixpkgs = {
      url = "git+https://github.com/NixOS/nixpkgs.git?ref=refs/heads/nixpkgs-unstable&shallow=1";
    };
    personal-nixpkgs = {
      url = "git+https://github.com/ren-lingyu/nixpkgs.git?ref=refs/heads/main&shallow=1";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    { self, ... }@inputs:
    inputs.personal-nixpkgs.lib.mkFlake inputs.nixpkgs
      ({ lib }: rec {
        inherit inputs;
        moduleLocation = __curPos.file;
        llib = { inherit (inputs.personal-nixpkgs.lib) tests packages; };
        lpkgs = import ./pkgs {
          inherit llib;
          inherit (specialArgs) src;
        };
        specialArgs = {
          src = lib.fileset.toSource {
            root = ./lisp;
            fileset = ./lisp;
          };
        };
      })
      (
        {
          src,
          llib,
          lpkgs,
          ...
        }:
        {
          systems = inputs.nixpkgs.lib.systems.flakeExposed;

          flake = {
            overlays = { inherit (lpkgs.overlays) emacsPackages; };
          };

          perSystem = { pkgs, ... }: {
            nixpkgs.overlays = [ lpkgs.overlays.legacy ];

            legacyPackages = pkgs.legacyPackages;

            packages = {
              org-roam-blog = pkgs.emacsPackages.org-roam-blog;
              emacs = pkgs.emacs-with-org-roam-blog;
            };

            checks = import ./tests {
              inherit src pkgs llib;
              emacs = pkgs.emacs-with-org-roam-blog;
            };

            devShells = {
              default = pkgs.mkShell {
                packages = [
                  (pkgs.emacsPackages.emacsWithPackages (ps: [
                    ps.org-roam-blog
                    ps.package-lint
                  ]))
                ];
              };
            };

            treefmt = {
              flakeCheck = false;
              settings.excludes = [
                ".gitignore"
                "LICENSE"
                "README.org"
                "flake.lock"
              ];
            };
          };
        }
      );
}
