{ config, lib, pkgs, manifest, getParams, ... }:

let
  params = getParams [ "git" ] { };
  required = n:
    params.${n} or (throw "manifest.params.git.${n} is required (name, email, signingKey differ per host)");
  gitName = required "name";
  gitEmail = required "email";
  signingKey = required "signingKey";
  format = params.format or (if config.programs.gpg.enable or false then "openpgp" else "ssh");
  gpgsign = params.gpgsign or true;
in
{
  home.packages = [ pkgs.gitFull ];

  home.file.".gitconfig".text = ''
    [user]
    	name = ${gitName}
    	email = ${gitEmail}
    	signingKey = "${signingKey}"
    [gpg]
    	format = ${format}
    [commit]
    	gpgsign = ${if gpgsign then "true" else "false"}
  '';
}
