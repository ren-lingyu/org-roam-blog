{ pkgs, emacs } : (

  pkgs.runCommand "org-roam-blog-ert" {
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
      testFile = "${./ert.el}";
    };
  })

)
