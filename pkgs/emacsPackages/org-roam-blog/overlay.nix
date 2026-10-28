{ extraArgs }: final_: prev_: {
  org-roam-blog = final_.callPackage ./package.nix { inherit (extraArgs) src; };
}
