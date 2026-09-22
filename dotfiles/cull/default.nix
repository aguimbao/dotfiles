{ lib, pkgs, ... }:

# Not in nixpkgs: built from source. Hashes are filled in via VM
# eval round-trip (lib.fakeHash reports got/want on mismatch).
let
  cull = pkgs.buildGoModule {
    pname = "cull";
    version = "0.9.0";
    src = pkgs.fetchFromGitHub {
      owner = "legostin";
      repo = "cull";
      rev = "v0.9.0";
      hash = lib.fakeHash;
    };
    vendorHash = lib.fakeHash;
  };
in
{
  home.packages = [ cull ];
}
