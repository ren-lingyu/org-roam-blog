{ pkgs, source, emacs } : (

  pkgs.runCommand "org-roam-blog-package-lint" {
    nativeBuildInputs = [
      emacs
      pkgs.guile
    ];
  } (pkgs.replaceVarsWith {
    src = ./run.scm;
    isExecutable = true;
    replacements = {
      guile = pkgs.lib.getExe pkgs.guile;
      emacs = pkgs.lib.getExe' emacs "emacs";
      source = "${source}";
    };
  })

)
