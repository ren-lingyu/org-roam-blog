{
  lib,
  src,
  melpaBuild,
  org,
  org-roam,
}:
melpaBuild {
  inherit src;
  pname = "org-roam-blog";
  version = "0.1.0";
  melpaVersion = "0.1.0";
  packageRequires = [
    org
    org-roam
  ];
  turnCompilationWarningToError = true;
  meta = {
    license = lib.licenses.gpl3Plus;
    platforms = lib.platforms.all;
  };
}
