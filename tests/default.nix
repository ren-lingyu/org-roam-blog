{
  pkgs,
  src,
  emacs,
  llib,
}:
llib.tests.mkChecks {
  root = ./.;
  overlayFile = "test-overlay.nix";
  separator = "-";
  args = {
    inherit (pkgs)
      lib
      runCommand
      replaceVarsWith
      guile
      emacsPackages
      ;
    inherit src emacs;
  };
}
