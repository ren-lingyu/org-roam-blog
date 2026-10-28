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

  outputs = { self, ... }@inputs : inputs.personal-nixpkgs.lib.mkFlake
    inputs.nixpkgs
    ({ lib }: {
      inherit inputs;
      moduleLocation = __curPos.file;
    })
    {

      systems = inputs.nixpkgs.lib.systems.flakeExposed;

      perSystem = { config, pkgs, ... } : let

        source = pkgs.lib.fileset.toSource {
          root = ./lisp;
          fileset = pkgs.lib.fileset.unions [
            ./lisp
          ];
        };

        emacsPackages = pkgs.emacsPackagesFor pkgs.emacs31;

        emacs = emacsPackages.emacsWithPackages (ps_ : (builtins.concatLists [
          (with ps_; [
            package-lint
          ])
          [ config.packages.default ]
        ]));

      in {

        packages = {
          default = emacsPackages.trivialBuild {
            pname = "org-roam-blog";
            version = "0.1.0";
            src = source;
            packageRequires = [
              emacsPackages.org
              emacsPackages.org-roam
            ];
            turnCompilationWarningToError = true;
          };
        };

        checks = import ./tests {
          inherit pkgs source emacs;
        };

        devShells = {
          default = pkgs.mkShell {
            packages = [
              emacs
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

    };

}
